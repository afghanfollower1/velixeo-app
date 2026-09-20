import { createHash } from 'node:crypto';
import type { Prisma, PrismaClient, User } from '@prisma/client';
import { UserStatus } from '@prisma/client';

export type AccountControlState='TEMP_SUSPENDED'|'PERM_SUSPENDED'|'DELETED_USER'|'DELETED_ADMIN';
export type AccountControlRecord={state:AccountControlState;reason?:string;until?:string|null;changedAt:string;changedBy?:string|null;originalPhoneHash?:string|null};

const userKey=(id:string)=>`account.user.${id}`;
export function normalizeAccountPhone(value?:string|null){const d=String(value??'').replace(/\D/g,'');return d?`+${d}`:''}
export function phoneHash(value?:string|null){const p=normalizeAccountPhone(value);return p?createHash('sha256').update(p).digest('hex'):''}
const phoneKey=(value:string)=>`account.blockedPhone.${phoneHash(value)}`;

function parseRecord(value:Prisma.JsonValue|null|undefined):AccountControlRecord|null{
 if(!value||typeof value!=='object'||Array.isArray(value))return null;
 const r=value as Record<string,unknown>,state=String(r.state??'') as AccountControlState;
 if(!['TEMP_SUSPENDED','PERM_SUSPENDED','DELETED_USER','DELETED_ADMIN'].includes(state))return null;
 return{state,reason:typeof r.reason==='string'?r.reason:undefined,until:typeof r.until==='string'?r.until:null,changedAt:typeof r.changedAt==='string'?r.changedAt:new Date(0).toISOString(),changedBy:typeof r.changedBy==='string'?r.changedBy:null,originalPhoneHash:typeof r.originalPhoneHash==='string'?r.originalPhoneHash:null};
}
export async function getAccountControl(p:PrismaClient,userId:string){const r=await p.systemSetting.findUnique({where:{key:userKey(userId)}});return parseRecord(r?.value)}
export async function clearAccountControl(p:PrismaClient,userId:string){await p.systemSetting.deleteMany({where:{key:userKey(userId)}})}

export async function isPhonePermanentlyBlocked(p:PrismaClient,value?:string|null){
 const phone=normalizeAccountPhone(value);if(!phone)return false;
 const r=await p.systemSetting.findUnique({where:{key:phoneKey(phone)}});
 if(!r?.value||typeof r.value!=='object'||Array.isArray(r.value))return false;
 return (r.value as Record<string,unknown>).permanent===true;
}
export async function permanentPhoneBlockDetails(p:PrismaClient,value?:string|null){
 const phone=normalizeAccountPhone(value);if(!phone)return null;
 const r=await p.systemSetting.findUnique({where:{key:phoneKey(phone)}});
 if(!r?.value||typeof r.value!=='object'||Array.isArray(r.value))return null;
 const d=r.value as Record<string,unknown>;if(d.permanent!==true)return null;
 return{phone,reason:typeof d.reason==='string'?d.reason:'',blockedAt:typeof d.blockedAt==='string'?d.blockedAt:r.createdAt.toISOString(),blockedByAdminId:typeof d.blockedByAdminId==='string'?d.blockedByAdminId:null};
}
export async function blockPhonePermanently(p:PrismaClient,value:string,adminId:string,reason:string){
 const phone=normalizeAccountPhone(value);if(!/^\+[1-9]\d{6,14}$/.test(phone))throw new Error('invalid_phone');
 const v={phone,permanent:true,reason:reason.trim()||'Blocked by administrator',blockedAt:new Date().toISOString(),blockedByAdminId:adminId} as Prisma.InputJsonValue;
 return p.systemSetting.upsert({where:{key:phoneKey(phone)},update:{category:'account-control',description:'Permanently blocked phone number',value:v},create:{key:phoneKey(phone),category:'account-control',description:'Permanently blocked phone number',value:v}});
}
export async function unblockPhone(p:PrismaClient,value:string){const phone=normalizeAccountPhone(value);if(phone)await p.systemSetting.deleteMany({where:{key:phoneKey(phone)}})}

export async function resolveEffectiveUserAccess(p:PrismaClient,user:Pick<User,'id'|'status'>){
 const control=await getAccountControl(p,user.id);
 if(!control)return{allowed:user.status===UserStatus.ACTIVE,code:user.status===UserStatus.ACTIVE?null:'account_suspended',state:user.status===UserStatus.ACTIVE?'ACTIVE':'SUSPENDED'};
 if(control.state==='TEMP_SUSPENDED'){
   const until=control.until?new Date(control.until):null;
   if(until&&Number.isFinite(until.getTime())&&until.getTime()<=Date.now()){
     await p.$transaction([p.user.update({where:{id:user.id},data:{status:UserStatus.ACTIVE}}),p.systemSetting.deleteMany({where:{key:userKey(user.id)}})]);
     return{allowed:true,code:null,state:'ACTIVE'};
   }
   return{allowed:false,code:'account_temporarily_suspended',state:control.state,until:control.until??null,reason:control.reason??null};
 }
 if(control.state==='PERM_SUSPENDED')return{allowed:false,code:'account_permanently_suspended',state:control.state,reason:control.reason??null};
 return{allowed:false,code:'account_deleted',state:control.state,reason:control.reason??null};
}

async function saveControl(p:PrismaClient,userId:string,value:AccountControlRecord,description:string){
 return p.systemSetting.upsert({where:{key:userKey(userId)},update:{category:'account-control',description,value:value as unknown as Prisma.InputJsonValue},create:{key:userKey(userId),category:'account-control',description,value:value as unknown as Prisma.InputJsonValue}});
}
export async function suspendUserTemporarily(p:PrismaClient,userId:string,adminId:string,until:Date,reason:string){
 if(!Number.isFinite(until.getTime())||until.getTime()<=Date.now())throw new Error('invalid_suspend_until');
 const v:AccountControlRecord={state:'TEMP_SUSPENDED',reason:reason.trim()||'Temporarily suspended by administrator',until:until.toISOString(),changedAt:new Date().toISOString(),changedBy:adminId};
 await p.user.update({where:{id:userId},data:{status:UserStatus.SUSPENDED}});
 await p.refreshToken.updateMany({where:{userId,revokedAt:null},data:{revokedAt:new Date()}});
 await saveControl(p,userId,v,'VELIXEO temporary account suspension');
}
export async function suspendUserPermanently(p:PrismaClient,userId:string,adminId:string,reason:string){
 const v:AccountControlRecord={state:'PERM_SUSPENDED',reason:reason.trim()||'Permanently suspended by administrator',until:null,changedAt:new Date().toISOString(),changedBy:adminId};
 await p.user.update({where:{id:userId},data:{status:UserStatus.SUSPENDED}});
 await p.refreshToken.updateMany({where:{userId,revokedAt:null},data:{revokedAt:new Date()}});
 await saveControl(p,userId,v,'VELIXEO permanent account suspension');
}
export async function restoreUserAccess(p:PrismaClient,userId:string){
 await p.$transaction([p.user.update({where:{id:userId},data:{status:UserStatus.ACTIVE}}),p.systemSetting.deleteMany({where:{key:userKey(userId)}})]);
}
export async function softDeleteUserAccount(p:PrismaClient,user:Pick<User,'id'|'phone'>,actor:'USER'|'ADMIN',actorId:string,reason:string){
 const now=new Date(),state:AccountControlState=actor==='USER'?'DELETED_USER':'DELETED_ADMIN';
 const v:AccountControlRecord={state,reason:reason.trim()||(actor==='USER'?'Deleted by user':'Deleted by administrator'),until:null,changedAt:now.toISOString(),changedBy:actorId,originalPhoneHash:phoneHash(user.phone)||null};
 await p.refreshToken.updateMany({where:{userId:user.id,revokedAt:null},data:{revokedAt:now}});
 await p.user.update({where:{id:user.id},data:{status:UserStatus.SUSPENDED,fullName:'Deleted user',email:null,phone:null,passwordHash:null,googleSubject:null,websiteUrl:null,countryCode:null,avatarPreset:'avatar_01',avatarUrl:null,avatarData:null,emailVerifiedAt:null,phoneVerifiedAt:null,twoFactorEnabled:false,twoFactorMethod:null,twoFactorVerifiedAt:null}});
 await saveControl(p,user.id,v,'Soft-deleted VELIXEO account tombstone');
}
