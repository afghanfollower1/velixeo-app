import { randomBytes } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { Prisma, PrismaClient, UserStatus, WalletEntryStatus, WalletEntryType } from '@prisma/client';

type AuthenticateHook=(request:FastifyRequest,reply:FastifyReply)=>Promise<unknown>;
export type ReferralSettings={enabled:boolean;rewardPercent:number;rewardTrigger:'WALLET_TOPUP'};
type InviteRecord={
 inviterId:string;
 inviteeId:string;
 code:string;
 status:'ACTIVE'|'INACTIVE'|'REGISTERED'|'REWARDED';
 rewardPercent?:number;
 qualifyingTopupAfn?:number;
 rewardAfn?:number;
 rewardCount?:number;
 createdAt:string;
 lastRewardAt?:string|null;
 rewardedAt?:string|null;
};

const SETTINGS_KEY='referral.settings';
const userCodeKey=(id:string)=>`referral.user.${id}`;
const codeKey=(code:string)=>`referral.code.${code}`;
const inviteKey=(inviteeId:string)=>`referral.invitee.${inviteeId}`;
const esc=(v:unknown)=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');

function jsonObject(value:Prisma.JsonValue|null|undefined){
 return value&&typeof value==='object'&&!Array.isArray(value)?value as Record<string,unknown>:{};
}
function clampPercent(value:unknown){
 const n=Number(value);
 if(!Number.isFinite(n))return 0;
 return Math.max(0,Math.min(100,Math.round(n*100)/100));
}
export async function getReferralSettings(p:PrismaClient):Promise<ReferralSettings>{
 const row=await p.systemSetting.findUnique({where:{key:SETTINGS_KEY}});
 const v=jsonObject(row?.value);
 // rewardAfn was the old registration-bonus setting. It is intentionally ignored.
 return{
  enabled:v.enabled!==false,
  rewardPercent:clampPercent(v.rewardPercent??0),
  rewardTrigger:'WALLET_TOPUP',
 };
}
export async function saveReferralSettings(p:PrismaClient,value:ReferralSettings){
 const normalized:ReferralSettings={
  enabled:value.enabled,
  rewardPercent:clampPercent(value.rewardPercent),
  rewardTrigger:'WALLET_TOPUP',
 };
 return p.systemSetting.upsert({
  where:{key:SETTINGS_KEY},
  update:{category:'referral',description:'VELIXEO referral commission settings: percentage of verified wallet top-ups',value:normalized as unknown as Prisma.InputJsonValue},
  create:{key:SETTINGS_KEY,category:'referral',description:'VELIXEO referral commission settings: percentage of verified wallet top-ups',value:normalized as unknown as Prisma.InputJsonValue},
 });
}
function randomCode(){return 'VXL-'+randomBytes(5).toString('hex').toUpperCase()}
export async function ensureReferralCode(p:PrismaClient,userId:string){
 const existing=await p.systemSetting.findUnique({where:{key:userCodeKey(userId)}});
 const ev=jsonObject(existing?.value);
 if(typeof ev.code==='string'&&ev.code)return ev.code;
 for(let attempt=0;attempt<8;attempt++){
  const code=randomCode();
  const collision=await p.systemSetting.findUnique({where:{key:codeKey(code)}});
  if(collision)continue;
  await p.$transaction([
   p.systemSetting.upsert({
    where:{key:userCodeKey(userId)},
    update:{category:'referral',value:{code,createdAt:new Date().toISOString()}},
    create:{key:userCodeKey(userId),category:'referral',description:'Referral code owned by user',value:{code,createdAt:new Date().toISOString()}},
   }),
   p.systemSetting.create({data:{key:codeKey(code),category:'referral-code',description:'Referral code index',value:{userId,code,createdAt:new Date().toISOString()}}}),
  ]);
  return code;
 }
 throw new Error('referral_code_generation_failed');
}
export async function resolveReferralCode(p:PrismaClient,raw?:string|null){
 const code=String(raw??'').trim().toUpperCase();
 if(!code)return null;
 const settings=await getReferralSettings(p);if(!settings.enabled)throw new Error('referral_program_disabled');
 const row=await p.systemSetting.findUnique({where:{key:codeKey(code)}});
 const v=jsonObject(row?.value),userId=typeof v.userId==='string'?v.userId:'';
 if(!userId)throw new Error('invalid_referral_code');
 const inviter=await p.user.findUnique({where:{id:userId}});
 if(!inviter||inviter.status!==UserStatus.ACTIVE)throw new Error('invalid_referral_code');
 return{code,inviterId:userId,settings};
}

/**
 * Registration only creates the referral relationship.
 * No wallet reward is ever paid here. Commission is paid only after a verified
 * wallet top-up and is idempotent per payment transaction.
 */
export async function recordReferralRegistration(
 p:PrismaClient,
 input:{inviteeId:string;inviterId:string;code:string;settings:ReferralSettings},
){
 if(input.inviteeId===input.inviterId)return null;
 const existing=await p.systemSetting.findUnique({where:{key:inviteKey(input.inviteeId)}});
 if(existing)return existing;
 const value:InviteRecord={
  inviterId:input.inviterId,
  inviteeId:input.inviteeId,
  code:input.code,
  status:'ACTIVE',
  rewardPercent:input.settings.rewardPercent,
  qualifyingTopupAfn:0,
  rewardAfn:0,
  rewardCount:0,
  createdAt:new Date().toISOString(),
  lastRewardAt:null,
 };
 return p.systemSetting.create({
  data:{
   key:inviteKey(input.inviteeId),
   category:'referral-invite',
   description:'VELIXEO referral relationship; rewards only on verified wallet top-ups',
   value:value as unknown as Prisma.InputJsonValue,
  },
 });
}

export async function grantReferralTopupCommission(
 p:PrismaClient,
 input:{inviteeId:string;paymentId:string;amountAfn:bigint},
){
 if(input.amountAfn<=0n)return null;
 const relation=await p.systemSetting.findUnique({where:{key:inviteKey(input.inviteeId)}});
 if(!relation)return null;
 const relationValue=jsonObject(relation.value);
 const inviterId=typeof relationValue.inviterId==='string'?relationValue.inviterId:'';
 if(!inviterId||inviterId===input.inviteeId)return null;

 const settings=await getReferralSettings(p);
 if(!settings.enabled||settings.rewardPercent<=0)return null;
 const basisPoints=BigInt(Math.round(settings.rewardPercent*100));
 const commission=(input.amountAfn*basisPoints)/10000n;
 if(commission<=0n)return null;
 const idempotencyKey=`referral-topup-${input.paymentId}`;

 return p.$transaction(async tx=>{
  const existing=await tx.walletEntry.findUnique({where:{idempotencyKey}});
  if(existing){
   return{inviterId,commissionAfn:existing.amountAfn,paymentId:input.paymentId,idempotent:true,rewardPercent:settings.rewardPercent};
  }

  const inviter=await tx.user.findUnique({where:{id:inviterId},select:{id:true,status:true}});
  if(!inviter||inviter.status!==UserStatus.ACTIVE)return null;
  const wallet=await tx.wallet.findUnique({where:{userId:inviterId}});
  if(!wallet)throw new Error('referral_wallet_not_found');

  const next=wallet.balanceAfn+commission;
  await tx.wallet.update({where:{id:wallet.id},data:{balanceAfn:next}});
  const entry=await tx.walletEntry.create({
   data:{
    walletId:wallet.id,
    type:WalletEntryType.MANUAL_CREDIT,
    status:WalletEntryStatus.COMPLETED,
    amountAfn:commission,
    balanceAfterAfn:next,
    referenceType:'REFERRAL_TOPUP_COMMISSION',
    referenceId:input.paymentId,
    description:`Referral commission ${settings.rewardPercent}% from verified wallet top-up`,
    idempotencyKey,
    metadata:{
     inviteeId:input.inviteeId,
     paymentId:input.paymentId,
     topupAfn:input.amountAfn.toString(),
     rewardPercent:settings.rewardPercent,
    },
   },
  });

  const fresh=await tx.systemSetting.findUnique({where:{key:inviteKey(input.inviteeId)}});
  const v=jsonObject(fresh?.value);
  const previousTopup=Math.max(0,Math.trunc(Number(v.qualifyingTopupAfn??0)||0));
  const previousReward=Math.max(0,Math.trunc(Number(v.rewardAfn??0)||0));
  const previousCount=Math.max(0,Math.trunc(Number(v.rewardCount??0)||0));
  await tx.systemSetting.update({
   where:{key:inviteKey(input.inviteeId)},
   data:{
    value:{
     ...v,
     status:'ACTIVE',
     rewardPercent:settings.rewardPercent,
     qualifyingTopupAfn:previousTopup+Number(input.amountAfn),
     rewardAfn:previousReward+Number(commission),
     rewardCount:previousCount+1,
     lastRewardAt:new Date().toISOString(),
    } as Prisma.InputJsonValue,
   },
  });

  return{inviterId,commissionAfn:entry.amountAfn,paymentId:input.paymentId,idempotent:false,rewardPercent:settings.rewardPercent};
 },{isolationLevel:Prisma.TransactionIsolationLevel.Serializable});
}

export async function referralAdminSnapshot(p:PrismaClient){
 const [settings,rows]=await Promise.all([
  getReferralSettings(p),
  p.systemSetting.findMany({where:{category:'referral-invite'},orderBy:{createdAt:'desc'},take:500}),
 ]);
 const items=rows.map(row=>jsonObject(row.value));
 const inviteeIds=[...new Set(items.map(x=>String(x.inviteeId??'')).filter(Boolean))];
 const inviterIds=[...new Set(items.map(x=>String(x.inviterId??'')).filter(Boolean))];
 const users=await p.user.findMany({
  where:{id:{in:[...new Set([...inviteeIds,...inviterIds])]}},
  select:{id:true,fullName:true,email:true,phone:true},
 });
 const map=new Map(users.map(x=>[x.id,x]));
 return{
  settings,
  items:items.map(x=>({...x,inviter:map.get(String(x.inviterId??''))??null,invitee:map.get(String(x.inviteeId??''))??null})),
  count:items.length,
  totalRewards:items.reduce((s,x)=>s+Math.max(0,Number(x.rewardAfn??0)||0),0),
  totalQualifyingTopups:items.reduce((s,x)=>s+Math.max(0,Number(x.qualifyingTopupAfn??0)||0),0),
 };
}

export function registerReferralRoutes(app:FastifyInstance,p:PrismaClient,authenticate:AuthenticateHook){
 app.get('/api/v1/referrals/me',{preHandler:authenticate},async(request,reply)=>{
  const userId=(request.user as {sub:string}).sub;
  const user=await p.user.findUnique({where:{id:userId}});
  if(!user)return reply.code(404).send({error:'user_not_found'});
  const settings=await getReferralSettings(p);
  const code=await ensureReferralCode(p,userId);
  const rows=await p.systemSetting.findMany({where:{category:'referral-invite'},orderBy:{createdAt:'desc'},take:1000});
  const mine=rows.map(r=>jsonObject(r.value)).filter(x=>x.inviterId===userId);
  const inviteeIds=mine.map(x=>String(x.inviteeId??'')).filter(Boolean);
  const invitees=inviteeIds.length
   ?await p.user.findMany({where:{id:{in:inviteeIds}},select:{id:true,fullName:true,createdAt:true}})
   :[];
  const map=new Map(invitees.map(x=>[x.id,x]));
  const base=(process.env.PUBLIC_BASE_URL||'https://velixeo-api-production.up.railway.app').replace(/\/$/,'');
  return{
   enabled:settings.enabled,
   code,
   inviteLink:`${base}/invite/${encodeURIComponent(code)}`,
   rewardPercent:settings.rewardPercent,
   inviteCount:mine.length,
   totalRewardsAfn:mine.reduce((s,x)=>s+Math.max(0,Number(x.rewardAfn??0)||0),0),
   totalQualifyingTopupsAfn:mine.reduce((s,x)=>s+Math.max(0,Number(x.qualifyingTopupAfn??0)||0),0),
   invites:mine.map(x=>({
    id:String(x.inviteeId??''),
    name:map.get(String(x.inviteeId??''))?.fullName||'VELIXEO user',
    status:String(x.status??'ACTIVE'),
    rewardAfn:Math.max(0,Number(x.rewardAfn??0)||0),
    qualifyingTopupAfn:Math.max(0,Number(x.qualifyingTopupAfn??0)||0),
    rewardCount:Math.max(0,Number(x.rewardCount??0)||0),
    createdAt:String(x.createdAt??''),
    lastRewardAt:x.lastRewardAt==null?null:String(x.lastRewardAt),
   })),
  };
 });
 app.get('/invite/:code',async(request,reply)=>{
  const code=String((request.params as {code?:string}).code??'').trim().toUpperCase();
  let valid=false;try{valid=Boolean(await resolveReferralCode(p,code))}catch{}
  const title=valid?'You were invited to VELIXEO':'VELIXEO invitation';
  const body=valid
   ?`Use referral code <b>${esc(code)}</b> when creating your VELIXEO account. Referral commission is earned only when the invited account completes a verified wallet top-up.`
   :'This invitation link is unavailable or expired.';
  return reply.type('text/html; charset=utf-8').send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font-family:system-ui;background:#f4f9ff;color:#102235;display:grid;place-items:center;min-height:100vh;margin:0}.card{width:min(520px,90vw);background:#fff;border:1px solid #dce8f1;border-radius:24px;padding:28px;text-align:center;box-shadow:0 14px 50px #163b6420}.v{width:64px;height:64px;border-radius:20px;background:linear-gradient(135deg,#31b5ff,#1686ff);color:#fff;display:grid;place-items:center;margin:auto;font-size:30px;font-weight:900}.code{margin:18px 0;padding:14px;border-radius:14px;background:#eef7ff;font:700 18px monospace}</style></head><body><div class="card"><div class="v">V</div><h1>${title}</h1><p>${body}</p>${valid?`<div class="code">${esc(code)}</div><p>Open VELIXEO → Create account → enter this code in “Referral code (optional)”.</p>`:''}</div></body></html>`);
 });
}
