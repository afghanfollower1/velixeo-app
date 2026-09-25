
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { Prisma, PrismaClient, ProviderKind, ServiceCategory } from '@prisma/client';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { brandSettingKey, defaultBrandIcons, loadSocialBrands, normalizeBrandKey } from './socialBrands.js';
import { inferSocialGroup, inferSocialPlatform, syncSocialProviderCatalog } from './socialSync.js';
import { renderAdminV3Page } from './adminFigmaEnglish.js';
import { adminLangFromRequest } from './adminLocale.js';
import { providerAverageEtaFromMetadata, providerStartEtaFromMetadata } from './socialEta.js';

type AdminIdentity={id:string;fullName:string|null;email:string|null;phone:string|null};
type AdminResolver=(request:FastifyRequest)=>Promise<AdminIdentity|null>;
type J=Record<string,unknown>;
type McpRequest={jsonrpc?:string;id?:string|number|null;method?:string;params?:J};
type CategoryRow={slug:string;titleEn:string;titleFa:string;descriptionEn:string;descriptionFa:string;platform:string;sortOrder:number;enabled:boolean;candidateKey:string};

const VERSION='1.2.1';
const TOKEN_KEY='chatgpt.mcp.token_hash';
const APPROVAL='I_CONFIRM';
const PROTOCOLS=['2026-07-28','2025-11-25','2025-06-18','2025-03-26'];

const BRAND:Record<string,{en:string;fa:string;icon:string}>={
 INSTAGRAM:{en:'Instagram',fa:'اینستاگرام',icon:'instagram'},
 FACEBOOK:{en:'Facebook',fa:'فیسبوک',icon:'facebook'},
 TIKTOK:{en:'TikTok',fa:'تیک‌تاک',icon:'tiktok'},
 YOUTUBE:{en:'YouTube',fa:'یوتیوب',icon:'youtube'},
 TELEGRAM:{en:'Telegram',fa:'تلگرام',icon:'telegram'},
 WHATSAPP:{en:'WhatsApp',fa:'واتساپ',icon:'whatsapp'},
 X:{en:'X / Twitter',fa:'ایکس / توییتر',icon:'x'},
 THREADS:{en:'Threads',fa:'تردز',icon:'threads'},
 SNAPCHAT:{en:'Snapchat',fa:'اسنپ‌چت',icon:'snapchat'},
 LINKEDIN:{en:'LinkedIn',fa:'لینکدین',icon:'linkedin'},
 PINTEREST:{en:'Pinterest',fa:'پینترست',icon:'pinterest'},
 DISCORD:{en:'Discord',fa:'دیسکورد',icon:'discord'},
 SPOTIFY:{en:'Spotify',fa:'اسپاتیفای',icon:'spotify'},
 SOUNDCLOUD:{en:'SoundCloud',fa:'ساندکلاد',icon:'soundcloud'}
};
const CAT:Record<string,{en:string;fa:string}>={
 FOLLOWERS_REFILL:{en:'Followers with Refill',fa:'فالوور با جبران'},
 FOLLOWERS_NO_REFILL:{en:'Followers without Refill',fa:'فالوور بدون جبران'},
 LIKES:{en:'Likes',fa:'لایک'},VIEWS:{en:'Views',fa:'بازدید'},
 COMMENTS:{en:'Comments',fa:'کامنت'},CUSTOM_COMMENTS:{en:'Custom Comments',fa:'کامنت دلخواه'},
 SHARES:{en:'Shares',fa:'اشتراک‌گذاری'},SAVES:{en:'Saves',fa:'ذخیره'},
 REACH:{en:'Reach & Impressions',fa:'ریچ و ایمپرشن'},POLL:{en:'Poll & Votes',fa:'نظرسنجی و رأی'},
 TRAFFIC:{en:'Traffic',fa:'ترافیک'},OTHER:{en:'Other',fa:'سایر'}
};

const obj=(v:Prisma.JsonValue|null|undefined):J=>v&&typeof v==='object'&&!Array.isArray(v)?v as J:{};
const safeSlug=(v:string)=>v.trim().toLowerCase().replace(/\s+/g,'-').replace(/[^a-z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').slice(0,80);
const normCat=(v:string)=>v.trim().toUpperCase().replace(/[^A-Z0-9_]+/g,'_').replace(/^_+|_+$/g,'');
const titleCase=(v:string)=>v.toLowerCase().split(/[_\s-]+/).filter(Boolean).map(p=>p.charAt(0).toUpperCase()+p.slice(1)).join(' ');
const hash=(v:string)=>createHash('sha256').update(v).digest('hex');
const catKey=(slug:string)=>'social.category.'+slug;

function brandLabel(key:string){
 const k=normalizeBrandKey(key);
 return BRAND[k]||{en:titleCase(k||'OTHER'),fa:titleCase(k||'OTHER'),icon:(defaultBrandIcons as readonly string[]).includes(k.toLowerCase())?k.toLowerCase():'generic'};
}
function catLabel(key:string){
 const k=normCat(key);
 return CAT[k]||{en:titleCase(k||'OTHER'),fa:titleCase(k||'OTHER')};
}
function equalToken(expectedHash:string,token:string){
 const a=Buffer.from(expectedHash,'hex'),b=Buffer.from(hash(token),'hex');
 return a.length===b.length&&timingSafeEqual(a,b);
}
async function savedHash(p:PrismaClient){
 const row=await p.systemSetting.findUnique({where:{key:TOKEN_KEY}});
 const v=obj(row?.value);
 return typeof v.sha256==='string'?v.sha256:'';
}
function requestToken(req:FastifyRequest){
 const auth=String(req.headers.authorization||'');
 if(auth.toLowerCase().startsWith('bearer '))return auth.slice(7).trim();
 const q=(req.query||{}) as Record<string,unknown>;
 return String(q.token||'').trim();
}
async function authorized(p:PrismaClient,req:FastifyRequest){
 const expected=await savedHash(p),token=requestToken(req);
 return Boolean(expected&&token&&equalToken(expected,token));
}
async function actor(p:PrismaClient):Promise<AdminIdentity>{
 const row=await p.systemSetting.findUnique({where:{key:TOKEN_KEY}});
 const v=obj(row?.value),createdBy=typeof v.createdBy==='string'?v.createdBy:'';
 if(createdBy){
  const u=await p.user.findUnique({where:{id:createdBy},select:{id:true,role:true,fullName:true,email:true,phone:true}});
  if(u&&u.role==='ADMIN')return {id:u.id,fullName:u.fullName,email:u.email,phone:u.phone};
 }
 const u=await p.user.findFirst({where:{role:'ADMIN'},orderBy:{createdAt:'asc'},select:{id:true,fullName:true,email:true,phone:true}});
 if(!u)throw new Error('ADMIN_NOT_FOUND');
 return u;
}
async function audit(p:PrismaClient,a:AdminIdentity,action:string,entityType:string,entityId:string|null,summary:string,metadata?:Prisma.InputJsonValue){
 await p.adminAuditLog.create({data:{adminUserId:a.id,action,entityType,entityId,summary,metadata}});
}
function needApproval(args:J){
 if(String(args.approval||'')!==APPROVAL)throw new Error('EXPLICIT_APPROVAL_REQUIRED:I_CONFIRM');
}
async function categories(p:PrismaClient):Promise<CategoryRow[]>{
 const rows=await p.systemSetting.findMany({where:{category:'social-category'},orderBy:{key:'asc'}});
 return rows.map(setting=>{
  const v=obj(setting.value),slug=String(v.slug||setting.key.replace(/^social\.category\./,''));
  return {slug,titleEn:String(v.titleEn||slug),titleFa:String(v.titleFa||v.titleEn||slug),descriptionEn:String(v.descriptionEn||''),descriptionFa:String(v.descriptionFa||''),platform:normalizeBrandKey(String(v.platform||'OTHER'))||'OTHER',sortOrder:Number.isFinite(Number(v.sortOrder))?Number(v.sortOrder):100,enabled:v.enabled!==false,candidateKey:normCat(String(v.aiCandidateKey||v.sourceCandidateKey||slug))};
 });
}
async function providerRoutes(p:PrismaClient,providerId:string){
 return p.serviceProviderRoute.findMany({where:{providerId,provider:{kind:ProviderKind.SOCIAL},service:{category:ServiceCategory.SOCIAL}},include:{provider:true,service:true},orderBy:[{providerServiceCode:'asc'}]});
}
function platformOf(route:{providerName:string|null;providerCategory:string|null;service:{titleEn:string;socialPlatform:string|null}}){
 const existing=normalizeBrandKey(route.service.socialPlatform||'');
 if(existing&&existing!=='OTHER')return existing;
 return normalizeBrandKey(inferSocialPlatform([route.providerName,route.providerCategory,route.service.titleEn].filter(Boolean).join(' ')))||'OTHER';
}
function candidateOf(route:{providerName:string|null;providerType:string|null;providerCategory:string|null;providerRefill:boolean;service:{titleEn:string;socialGroup:string|null}}){
 const text=[route.providerName,route.providerType,route.providerCategory,route.service.titleEn].filter(Boolean).join(' ');
 if(/custom\s*comments?|comments?\s*custom/i.test(text))return 'CUSTOM_COMMENTS';
 const inferred=normCat(inferSocialGroup(text));
 if(inferred==='FOLLOWERS')return route.providerRefill?'FOLLOWERS_REFILL':'FOLLOWERS_NO_REFILL';
 return inferred||'OTHER';
}
async function listProviders(p:PrismaClient){
 const rows=await p.provider.findMany({where:{kind:ProviderKind.SOCIAL},orderBy:[{enabled:'desc'},{priority:'asc'},{name:'asc'}],select:{id:true,name:true,slug:true,enabled:true,currencyCode:true,priority:true,defaultMarkupPercent:true}});
 const providers=[];
 for(const row of rows)providers.push({...row,defaultMarkupPercent:row.defaultMarkupPercent.toString(),syncedServiceCount:await p.serviceProviderRoute.count({where:{providerId:row.id}})});
 return {providers};
}
async function discoverBrands(p:PrismaClient,providerId:string){
 const routes=await providerRoutes(p,providerId),map=new Map<string,{count:number;examples:string[]}>();
 for(const r of routes){
  const key=platformOf(r);if(key==='OTHER')continue;
  const v=map.get(key)||{count:0,examples:[]};v.count++;
  if(v.examples.length<4)v.examples.push(r.providerName||r.service.titleEn);
  map.set(key,v);
 }
 const existing=new Set((await loadSocialBrands(p)).map(b=>b.key));
 return {providerId,totalSyncedServices:routes.length,brands:[...map.entries()].map(([key,v])=>({key,titleEn:brandLabel(key).en,titleFa:brandLabel(key).fa,serviceCount:v.count,alreadyCreated:existing.has(key),examples:v.examples})).sort((a,b)=>b.serviceCount-a.serviceCount)};
}
async function saveBrands(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const providerId=String(args.provider_id||''),raw=Array.isArray(args.brand_keys)?args.brand_keys:[],keys=[...new Set(raw.map(v=>normalizeBrandKey(String(v))).filter(Boolean))];
 if(!providerId||!keys.length)throw new Error('PROVIDER_AND_BRANDS_REQUIRED');
 const provider=await p.provider.findFirst({where:{id:providerId,kind:ProviderKind.SOCIAL},select:{id:true,name:true}});
 if(!provider)throw new Error('SOCIAL_PROVIDER_NOT_FOUND');
 const oldBrands=await loadSocialBrands(p);let order=Math.max(0,...oldBrands.map(b=>b.sortOrder))+10;const saved=[];
 for(const key of keys){
  const label=brandLabel(key),settingKey=brandSettingKey(key),old=await p.systemSetting.findUnique({where:{key:settingKey}}),oldV=obj(old?.value);
  const value={key,titleEn:label.en,titleFa:label.fa,iconType:'DEFAULT',iconValue:label.icon,sortOrder:Number.isFinite(Number(oldV.sortOrder))?Number(oldV.sortOrder):order,enabled:true,sourceProviderId:providerId,createdByChatGPT:true};
  await p.systemSetting.upsert({where:{key:settingKey},create:{key:settingKey,category:'social-brand',description:'Social Media customer-facing brand.',value:value as unknown as Prisma.InputJsonValue},update:{category:'social-brand',value:value as unknown as Prisma.InputJsonValue}});
  saved.push({key,titleEn:label.en,titleFa:label.fa,created:!old});order+=10;
 }
 await audit(p,a,'CHATGPT_SOCIAL_BRANDS_SAVE','SocialBrand',null,'ChatGPT saved '+saved.length+' social brands from '+provider.name,{providerId,saved} as unknown as Prisma.InputJsonValue);
 return {providerId,providerName:provider.name,saved};
}
async function discoverCategories(p:PrismaClient,providerId:string,brandInput:string){
 const brandKey=normalizeBrandKey(brandInput),routes=(await providerRoutes(p,providerId)).filter(r=>platformOf(r)===brandKey);
 const map=new Map<string,{count:number;refill:number;noRefill:number;examples:string[];providerCategories:Set<string>}>();
 for(const r of routes){
  const key=candidateOf(r),v=map.get(key)||{count:0,refill:0,noRefill:0,examples:[],providerCategories:new Set<string>()};
  v.count++;if(r.providerRefill)v.refill++;else v.noRefill++;
  if(v.examples.length<5)v.examples.push(r.providerName||r.service.titleEn);
  if(r.providerCategory)v.providerCategories.add(r.providerCategory);map.set(key,v);
 }
 const old=await categories(p);
 return {providerId,brandKey,brand:brandLabel(brandKey),totalServices:routes.length,categories:[...map.entries()].map(([key,v])=>({candidateKey:key,titleEn:catLabel(key).en,titleFa:catLabel(key).fa,suggestedSlug:safeSlug(brandKey+'-'+key),serviceCount:v.count,refillCount:v.refill,noRefillCount:v.noRefill,alreadyCreated:old.some(c=>c.platform===brandKey&&c.candidateKey===key),providerCategories:[...v.providerCategories].slice(0,20),examples:v.examples})).sort((a,b)=>b.serviceCount-a.serviceCount)};
}
async function saveCategories(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const brandKey=normalizeBrandKey(String(args.brand_key||'')),rows=Array.isArray(args.categories)?args.categories:[];
 if(!brandKey||!rows.length)throw new Error('BRAND_AND_CATEGORIES_REQUIRED');
 const brands=await loadSocialBrands(p);if(!brands.some(b=>b.key===brandKey))throw new Error('BRAND_NOT_CREATED');
 const old=await categories(p);let order=Math.max(0,...old.filter(c=>c.platform===brandKey).map(c=>c.sortOrder))+10;const saved=[];
 for(const item of rows){
  if(!item||typeof item!=='object'||Array.isArray(item))continue;
  const row=item as J,candidateKey=normCat(String(row.candidate_key||'')),label=catLabel(candidateKey),slug=safeSlug(String(row.slug||'')||brandKey+'-'+candidateKey);
  if(!candidateKey||!slug)continue;
  const titleEn=String(row.title_en||'').trim()||label.en,titleFa=String(row.title_fa||'').trim()||label.fa;
  const descriptionEn=String(row.description_en||'').trim(),descriptionFa=String(row.description_fa||'').trim();
  const value={slug,titleEn,titleFa,platform:brandKey,descriptionEn,descriptionFa,sortOrder:order,enabled:true,aiCandidateKey:candidateKey,createdByChatGPT:true};
  const key=catKey(slug),existing=await p.systemSetting.findUnique({where:{key}});
  await p.systemSetting.upsert({where:{key},create:{key,category:'social-category',description:'Social Media customer-facing category.',value:value as unknown as Prisma.InputJsonValue},update:{category:'social-category',value:value as unknown as Prisma.InputJsonValue}});
  saved.push({slug,candidateKey,titleEn,titleFa,descriptionEn,descriptionFa,created:!existing});order+=10;
 }
 await audit(p,a,'CHATGPT_SOCIAL_CATEGORIES_SAVE','SocialCategory',null,'ChatGPT saved '+saved.length+' categories under '+brandKey,{brandKey,saved} as unknown as Prisma.InputJsonValue);
 return {brandKey,saved};
}
async function listCandidateServices(p:PrismaClient,args:J){
 const providerId=String(args.provider_id||''),brandKey=normalizeBrandKey(String(args.brand_key||'')),candidateKey=normCat(String(args.candidate_key||'')),offset=Math.max(0,Math.floor(Number(args.offset||0))),limit=Math.max(1,Math.min(100,Math.floor(Number(args.limit||50))));
 const routes=(await providerRoutes(p,providerId)).filter(r=>platformOf(r)===brandKey&&candidateOf(r)===candidateKey),page=routes.slice(offset,offset+limit);
 return {providerId,brandKey,candidateKey,total:routes.length,offset,limit,hasMore:offset+page.length<routes.length,services:page.map(r=>{const eta=providerStartEtaFromMetadata(r.metadata,r.providerName),avg=providerAverageEtaFromMetadata(r.metadata);return {routeId:r.id,serviceId:r.serviceId,providerServiceId:r.providerServiceCode,providerName:r.providerName||r.service.titleEn,providerCategory:r.providerCategory,providerType:r.providerType,providerRate:r.providerRate?.toString()||null,providerCurrency:r.providerCurrency,min:r.providerMinQty,max:r.providerMaxQty,refill:r.providerRefill,cancel:r.providerCancel,providerStartTime:eta?.text||null,providerStartMinMinutes:eta?.minMinutes??null,providerStartMaxMinutes:eta?.maxMinutes??null,providerAverageTime:avg?.text||null,providerAverageMinMinutes:avg?.minMinutes??null,providerAverageMaxMinutes:avg?.maxMinutes??null,lastSyncedAt:r.lastSyncedAt?.toISOString()||null,markupPercent:r.markupPercent?.toString()??r.provider.defaultMarkupPercent.toString(),alreadyAdded:obj(r.service.metadata).rawCatalog!==true,existingTitleEn:r.service.titleEn,existingTitleFa:r.service.titleFa,existingDescriptionEn:r.service.descriptionEn,existingDescriptionFa:r.service.descriptionFa};})};
}
async function publishServices(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const providerId=String(args.provider_id||''),brandKey=normalizeBrandKey(String(args.brand_key||'')),categorySlug=safeSlug(String(args.category_slug||'')),candidateKey=normCat(String(args.candidate_key||'')),markupNumber=Number(args.markup_percent),items=Array.isArray(args.items)?args.items:[],enabled=args.enabled!==false;
 if(!providerId||!brandKey||!categorySlug||!candidateKey||!items.length)throw new Error('PUBLISH_ARGUMENTS_REQUIRED');
 if(!Number.isFinite(markupNumber)||markupNumber<0||markupNumber>1000)throw new Error('MARKUP_PERCENT_OUT_OF_RANGE');
 const category=(await categories(p)).find(c=>c.slug===categorySlug);if(!category)throw new Error('CATEGORY_NOT_FOUND');if(category.platform!==brandKey)throw new Error('CATEGORY_BRAND_MISMATCH');
 const routes=await providerRoutes(p,providerId),byCode=new Map(routes.map(r=>[r.providerServiceCode,r])),markup=new Prisma.Decimal(markupNumber),saved=[];
 for(const item of items){
  if(!item||typeof item!=='object'||Array.isArray(item))continue;
  const row=item as J,providerServiceId=String(row.provider_service_id||'').trim(),r=byCode.get(providerServiceId);if(!r)throw new Error('PROVIDER_SERVICE_NOT_FOUND:'+providerServiceId);
  if(platformOf(r)!==brandKey||candidateOf(r)!==candidateKey)throw new Error('SERVICE_OUTSIDE_SELECTED_CATEGORY:'+providerServiceId);
  const titleEn=String(row.title_en||'').trim(),titleFa=String(row.title_fa||'').trim(),descriptionEn=String(row.description_en||'').trim(),descriptionFa=String(row.description_fa||'').trim();if(!titleEn||!titleFa)throw new Error('BILINGUAL_TITLES_REQUIRED:'+providerServiceId);
  const sm=obj(r.service.metadata),rm=obj(r.metadata),drip=typeof rm._providerDripFeedDetected==='boolean'?rm._providerDripFeedDetected:Boolean(rm.dripfeed??rm.drip_feed),wasRaw=sm.rawCatalog===true;
  const startEta=providerStartEtaFromMetadata(r.metadata,r.providerName);
  await p.$transaction([
   p.service.update({where:{id:r.serviceId},data:{titleEn,titleFa,descriptionEn:descriptionEn||null,descriptionFa:descriptionFa||null,enabled,basePriceAfn:null,minQty:r.providerMinQty,maxQty:r.providerMaxQty,estimatedMinMinutes:startEta?.minMinutes??r.service.estimatedMinMinutes,estimatedMaxMinutes:startEta?.maxMinutes??r.service.estimatedMaxMinutes,socialPlatform:brandKey,socialGroup:category.slug,metadata:{...sm,rawCatalog:false,addedToVelixeo:true,pricingMode:'AUTO_MARKUP',categorySlug:category.slug,publishedFromProviderId:providerId,publishedAt:String(sm.publishedAt||new Date().toISOString()),managedByChatGPT:true,aiCandidateKey:candidateKey} as Prisma.InputJsonValue}}),
   p.serviceProviderRoute.update({where:{id:r.id},data:{enabled:true,markupPercent:markup,metadata:{...rm,_providerRefillDetected:typeof rm._providerRefillDetected==='boolean'?rm._providerRefillDetected:r.providerRefill,_velixeoRefillOverride:typeof rm._velixeoRefillOverride==='boolean'?rm._velixeoRefillOverride:r.providerRefill,_providerDripFeedDetected:drip,_velixeoDripFeedOverride:typeof rm._velixeoDripFeedOverride==='boolean'?rm._velixeoDripFeedOverride:drip} as Prisma.InputJsonValue}})
  ]);
  saved.push({providerServiceId,serviceId:r.serviceId,titleEn,titleFa,descriptionEn,descriptionFa,createdFromRawCatalog:wasRaw});
 }
 await audit(p,a,'CHATGPT_SOCIAL_SERVICES_PUBLISH','Service',null,'ChatGPT published '+saved.length+' services to '+category.titleEn+' with '+markupNumber+'% markup',{providerId,brandKey,candidateKey,categorySlug,markupPercent:markupNumber,enabled,serviceIds:saved.map(v=>v.serviceId)} as unknown as Prisma.InputJsonValue);
 return {providerId,brandKey,candidateKey,categorySlug,markupPercent:markupNumber,enabled,savedCount:saved.length,saved};
}
async function updateCategoryContent(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const slug=safeSlug(String(args.category_slug||''));if(!slug)throw new Error('CATEGORY_SLUG_REQUIRED');
 const key=catKey(slug),row=await p.systemSetting.findUnique({where:{key}});if(!row)throw new Error('CATEGORY_NOT_FOUND');
 const value=obj(row.value),next={...value,
  ...(args.title_en!==undefined?{titleEn:String(args.title_en||'').trim()}:{ }),
  ...(args.title_fa!==undefined?{titleFa:String(args.title_fa||'').trim()}:{ }),
  ...(args.description_en!==undefined?{descriptionEn:String(args.description_en||'').trim()}:{ }),
  ...(args.description_fa!==undefined?{descriptionFa:String(args.description_fa||'').trim()}:{ })
 };
 await p.systemSetting.update({where:{key},data:{value:next as Prisma.InputJsonValue}});
 await audit(p,a,'CHATGPT_SOCIAL_CATEGORY_CONTENT_UPDATE','SocialCategory',slug,'ChatGPT updated bilingual category content',{slug} as unknown as Prisma.InputJsonValue);
 return {slug,titleEn:String(next.titleEn||''),titleFa:String(next.titleFa||''),descriptionEn:String(next.descriptionEn||''),descriptionFa:String(next.descriptionFa||'')};
}
async function updateCategory(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const slug=safeSlug(String(args.category_slug||''));if(!slug)throw new Error('CATEGORY_SLUG_REQUIRED');
 const key=catKey(slug),row=await p.systemSetting.findUnique({where:{key}});if(!row)throw new Error('CATEGORY_NOT_FOUND');
 const value=obj(row.value),newSlug=safeSlug(String(args.new_slug??slug))||slug;
 const platform=args.platform!==undefined?normalizeBrandKey(String(args.platform||'')):normalizeBrandKey(String(value.platform||'OTHER'));
 const next={...value,slug:newSlug,platform,
  ...(args.title_en!==undefined?{titleEn:String(args.title_en||'').trim()}:{ }),
  ...(args.title_fa!==undefined?{titleFa:String(args.title_fa||'').trim()}:{ }),
  ...(args.description_en!==undefined?{descriptionEn:String(args.description_en||'').trim()}:{ }),
  ...(args.description_fa!==undefined?{descriptionFa:String(args.description_fa||'').trim()}:{ }),
  ...(args.sort_order!==undefined?{sortOrder:Number.isFinite(Number(args.sort_order))?Math.floor(Number(args.sort_order)):Number(value.sortOrder||100)}:{ }),
  ...(args.enabled!==undefined?{enabled:Boolean(args.enabled)}:{ })
 };
 let affectedServices=0;
 if(newSlug!==slug){
  const exists=await p.systemSetting.findUnique({where:{key:catKey(newSlug)}});if(exists)throw new Error('CATEGORY_SLUG_ALREADY_EXISTS');
  const moved=await p.$transaction(async tx=>{
   await tx.systemSetting.create({data:{key:catKey(newSlug),category:'social-category',description:'Social Media customer-facing category.',value:next as Prisma.InputJsonValue}});
   const changed=await tx.service.updateMany({where:{category:ServiceCategory.SOCIAL,socialGroup:slug},data:{socialGroup:newSlug,socialPlatform:platform}});
   await tx.systemSetting.delete({where:{key}});
   return changed.count;
  });
  affectedServices=moved;
 }else{
  await p.systemSetting.update({where:{key},data:{value:next as Prisma.InputJsonValue}});
  if(args.platform!==undefined){
   const changed=await p.service.updateMany({where:{category:ServiceCategory.SOCIAL,socialGroup:slug},data:{socialPlatform:platform}});
   affectedServices=changed.count;
  }
 }
 await audit(p,a,'CHATGPT_SOCIAL_CATEGORY_UPDATE','SocialCategory',newSlug,'ChatGPT updated social category',{oldSlug:slug,newSlug,platform,affectedServices} as unknown as Prisma.InputJsonValue);
 return {slug:newSlug,oldSlug:slug,renamed:newSlug!==slug,titleEn:String(next.titleEn||''),titleFa:String(next.titleFa||''),descriptionEn:String(next.descriptionEn||''),descriptionFa:String(next.descriptionFa||''),platform,sortOrder:Number(next.sortOrder||100),enabled:next.enabled!==false,affectedServices};
}
async function deleteCategory(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const slug=safeSlug(String(args.category_slug||''));if(!slug)throw new Error('CATEGORY_SLUG_REQUIRED');
 const key=catKey(slug),row=await p.systemSetting.findUnique({where:{key}});if(!row)throw new Error('CATEGORY_NOT_FOUND');
 const disabledServiceCount=await p.$transaction(async tx=>{
  const disabled=await tx.service.updateMany({where:{category:ServiceCategory.SOCIAL,socialGroup:slug},data:{enabled:false}});
  await tx.systemSetting.delete({where:{key}});
  return disabled.count;
 });
 await audit(p,a,'CHATGPT_SOCIAL_CATEGORY_DELETE','SocialCategory',slug,'ChatGPT deleted category and disabled '+disabledServiceCount+' services',{slug,disabledServiceCount} as unknown as Prisma.InputJsonValue);
 return {deleted:true,slug,disabledServiceCount};
}
async function updateServiceContent(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const serviceId=String(args.service_id||'').trim();if(!serviceId)throw new Error('SERVICE_ID_REQUIRED');
 const service=await p.service.findFirst({where:{id:serviceId,category:ServiceCategory.SOCIAL}});if(!service)throw new Error('SOCIAL_SERVICE_NOT_FOUND');
 const data:Prisma.ServiceUpdateInput={};
 if(args.title_en!==undefined)data.titleEn=String(args.title_en||'').trim();
 if(args.title_fa!==undefined)data.titleFa=String(args.title_fa||'').trim();
 if(args.description_en!==undefined)data.descriptionEn=String(args.description_en||'').trim()||null;
 if(args.description_fa!==undefined)data.descriptionFa=String(args.description_fa||'').trim()||null;
 const saved=await p.service.update({where:{id:serviceId},data});
 await audit(p,a,'CHATGPT_SOCIAL_SERVICE_CONTENT_UPDATE','Service',serviceId,'ChatGPT updated bilingual service content',{serviceId} as unknown as Prisma.InputJsonValue);
 return {serviceId,titleEn:saved.titleEn,titleFa:saved.titleFa,descriptionEn:saved.descriptionEn,descriptionFa:saved.descriptionFa};
}
async function listVelixeoServices(p:PrismaClient,args:J){
 const brandKey=normalizeBrandKey(String(args.brand_key||'')),categorySlug=safeSlug(String(args.category_slug||'')),q=String(args.q||'').trim(),limit=Math.max(1,Math.min(200,Math.floor(Number(args.limit||100))));
 const rows=await p.service.findMany({where:{category:ServiceCategory.SOCIAL,...(brandKey?{socialPlatform:brandKey}:{}),...(categorySlug?{socialGroup:categorySlug}:{}),...(q?{OR:[{titleEn:{contains:q,mode:'insensitive'}},{titleFa:{contains:q,mode:'insensitive'}},{slug:{contains:q,mode:'insensitive'}}]}:{})},include:{routes:{include:{provider:{select:{id:true,name:true}}},orderBy:{priority:'asc'}}},orderBy:[{enabled:'desc'},{sortOrder:'asc'},{titleEn:'asc'}],take:limit});
 return {count:rows.length,services:rows.map(service=>({id:service.id,slug:service.slug,titleEn:service.titleEn,titleFa:service.titleFa,descriptionEn:service.descriptionEn,descriptionFa:service.descriptionFa,enabled:service.enabled,platform:service.socialPlatform,categorySlug:service.socialGroup,estimatedMinMinutes:service.estimatedMinMinutes,estimatedMaxMinutes:service.estimatedMaxMinutes,routes:service.routes.map(r=>{const eta=providerStartEtaFromMetadata(r.metadata,r.providerName);return {routeId:r.id,providerId:r.providerId,providerName:r.provider.name,providerServiceId:r.providerServiceCode,markupPercent:r.markupPercent?.toString()||null,refill:r.providerRefill,cancel:r.providerCancel,providerStartTime:eta?.text||null};})}))};
}

async function setMarkup(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const categorySlug=safeSlug(String(args.category_slug||'')),markupNumber=Number(args.markup_percent);
 if(!categorySlug)throw new Error('CATEGORY_SLUG_REQUIRED');if(!Number.isFinite(markupNumber)||markupNumber<0||markupNumber>1000)throw new Error('MARKUP_PERCENT_OUT_OF_RANGE');
 const services=await p.service.findMany({where:{category:ServiceCategory.SOCIAL,socialGroup:categorySlug},select:{id:true}}),ids=services.map(s=>s.id);
 const result=ids.length?await p.serviceProviderRoute.updateMany({where:{serviceId:{in:ids}},data:{markupPercent:new Prisma.Decimal(markupNumber)}}):{count:0};
 await audit(p,a,'CHATGPT_SOCIAL_CATEGORY_MARKUP','SocialCategory',categorySlug,'ChatGPT set '+markupNumber+'% markup on '+result.count+' routes',{categorySlug,markupPercent:markupNumber,affectedRoutes:result.count} as unknown as Prisma.InputJsonValue);
 return {categorySlug,markupPercent:markupNumber,serviceCount:ids.length,affectedRoutes:result.count};
}
async function structure(p:PrismaClient){
 const brands=await loadSocialBrands(p),cats=await categories(p);
 return {brands:brands.map(b=>({key:b.key,titleEn:b.titleEn,titleFa:b.titleFa,enabled:b.enabled,categories:cats.filter(c=>c.platform===b.key).map(c=>({slug:c.slug,titleEn:c.titleEn,titleFa:c.titleFa,descriptionEn:c.descriptionEn,descriptionFa:c.descriptionFa,enabled:c.enabled,candidateKey:c.candidateKey}))}))};
}
async function syncProvider(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);const providerId=String(args.provider_id||''),result=await syncSocialProviderCatalog(p,providerId);
 await audit(p,a,'CHATGPT_SOCIAL_PROVIDER_SYNC','Provider',providerId,'ChatGPT synchronized '+result.total+' provider services',result as unknown as Prisma.InputJsonValue);
 return result;
}

const tools=[
 {name:'agent_diagnostics',description:'Read VELIXEO connector version, MCP protocols, tools and write approval coverage. Read-only.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}},
 {name:'list_social_providers',description:'List Social Media providers with IDs and synced service counts. Read-only.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}},
 {name:'sync_social_provider',description:'Synchronize one Social Media provider catalog. Requires explicit approval.',inputSchema:{type:'object',properties:{provider_id:{type:'string'},approval:{type:'string',enum:[APPROVAL]}},required:['provider_id','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'discover_provider_brands',description:'Detect brands in a synchronized provider catalog with service counts. Read-only.',inputSchema:{type:'object',properties:{provider_id:{type:'string'}},required:['provider_id'],additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}},
 {name:'create_social_brands',description:'Create selected customer-facing Social Media brands. Requires explicit approval.',inputSchema:{type:'object',properties:{provider_id:{type:'string'},brand_keys:{type:'array',items:{type:'string'}},approval:{type:'string',enum:[APPROVAL]}},required:['provider_id','brand_keys','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'discover_brand_categories',description:'Analyze one provider brand into categories such as Followers with Refill, Followers without Refill, Likes, Views and Custom Comments. Read-only.',inputSchema:{type:'object',properties:{provider_id:{type:'string'},brand_key:{type:'string'}},required:['provider_id','brand_key'],additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}},
 {name:'create_social_categories',description:'Create selected bilingual categories under a Social Media brand, including optional Persian and English descriptions. Requires explicit approval.',inputSchema:{type:'object',properties:{brand_key:{type:'string'},categories:{type:'array',items:{type:'object',properties:{candidate_key:{type:'string'},slug:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'}},required:['candidate_key','slug','title_en','title_fa'],additionalProperties:false}},approval:{type:'string',enum:[APPROVAL]}},required:['brand_key','categories','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'list_category_services',description:'List provider services for a detected brand/category with price, refill, cancel and IDs. Read-only and paginated.',inputSchema:{type:'object',properties:{provider_id:{type:'string'},brand_key:{type:'string'},candidate_key:{type:'string'},offset:{type:'integer',minimum:0},limit:{type:'integer',minimum:1,maximum:100}},required:['provider_id','brand_key','candidate_key'],additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}},
 {name:'publish_social_services',description:'Publish selected provider services with bilingual titles, optional bilingual descriptions, provider start-time metadata, and the exact markup specified by the administrator. Never infer markup. Requires explicit approval.',inputSchema:{type:'object',properties:{provider_id:{type:'string'},brand_key:{type:'string'},category_slug:{type:'string'},candidate_key:{type:'string'},markup_percent:{type:'number',minimum:0,maximum:1000},enabled:{type:'boolean'},items:{type:'array',maxItems:100,items:{type:'object',properties:{provider_service_id:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'}},required:['provider_service_id','title_en','title_fa'],additionalProperties:false}},approval:{type:'string',enum:[APPROVAL]}},required:['provider_id','brand_key','category_slug','candidate_key','markup_percent','enabled','items','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'set_category_markup',description:'Set the exact administrator-specified markup on already-added routes in one category. Requires explicit approval.',inputSchema:{type:'object',properties:{category_slug:{type:'string'},markup_percent:{type:'number',minimum:0,maximum:1000},approval:{type:'string',enum:[APPROVAL]}},required:['category_slug','markup_percent','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'update_social_category_content',description:'Update Persian/English title and description fields for an existing Social Media category. Requires explicit approval.',inputSchema:{type:'object',properties:{category_slug:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'},approval:{type:'string',enum:[APPROVAL]}},required:['category_slug','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'update_social_category',description:'Edit an existing Social Media category, including slug, platform, bilingual title/description, display order and enabled status. Renaming a slug migrates assigned services. Requires explicit approval.',inputSchema:{type:'object',properties:{category_slug:{type:'string'},new_slug:{type:'string'},platform:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'},sort_order:{type:'integer'},enabled:{type:'boolean'},approval:{type:'string',enum:[APPROVAL]}},required:['category_slug','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'delete_social_category',description:'Delete a Social Media category and disable all VELIXEO services currently assigned to it so they cannot become uncategorized customer-visible services. Requires explicit approval.',inputSchema:{type:'object',properties:{category_slug:{type:'string'},approval:{type:'string',enum:[APPROVAL]}},required:['category_slug','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:true}},
 {name:'update_social_service_content',description:'Update Persian/English title and description fields for an existing VELIXEO Social Media service. Requires explicit approval.',inputSchema:{type:'object',properties:{service_id:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'},approval:{type:'string',enum:[APPROVAL]}},required:['service_id','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'list_velixeo_social_services',description:'List already-added VELIXEO Social Media services with bilingual descriptions, provider routing, markup and estimated provider start time. Read-only.',inputSchema:{type:'object',properties:{brand_key:{type:'string'},category_slug:{type:'string'},q:{type:'string'},limit:{type:'integer',minimum:1,maximum:200}},additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}},
 {name:'show_social_structure',description:'Show current VELIXEO Social Media brands and categories. Read-only.',inputSchema:{type:'object',properties:{},additionalProperties:false},annotations:{readOnlyHint:true,destructiveHint:false}}
] as const;

function result(value:unknown){
 const structured=value&&typeof value==='object'&&!Array.isArray(value)?value as J:{value};
 return {content:[{type:'text',text:JSON.stringify(structured)}],structuredContent:structured};
}
function toolError(error:unknown){
 const message=error instanceof Error?error.message:'tool_failed';
 return {content:[{type:'text',text:JSON.stringify({ok:false,error:message})}],structuredContent:{ok:false,error:message},isError:true};
}
async function execute(p:PrismaClient,a:AdminIdentity,name:string,args:J){
 if(name==='agent_diagnostics')return {plugin_version:VERSION,server_version:VERSION,protocol_versions:PROTOCOLS,tool_count:tools.length,write_approval_coverage:tools.filter(t=>t.annotations.readOnlyHint===false).map(t=>({name:t.name,approval:APPROVAL})),tools:tools.map(t=>t.name)};
 if(name==='list_social_providers')return listProviders(p);
 if(name==='sync_social_provider')return syncProvider(p,a,args);
 if(name==='discover_provider_brands')return discoverBrands(p,String(args.provider_id||''));
 if(name==='create_social_brands')return saveBrands(p,a,args);
 if(name==='discover_brand_categories')return discoverCategories(p,String(args.provider_id||''),String(args.brand_key||''));
 if(name==='create_social_categories')return saveCategories(p,a,args);
 if(name==='list_category_services')return listCandidateServices(p,args);
 if(name==='publish_social_services')return publishServices(p,a,args);
 if(name==='set_category_markup')return setMarkup(p,a,args);
 if(name==='update_social_category_content')return updateCategoryContent(p,a,args);
 if(name==='update_social_category')return updateCategory(p,a,args);
 if(name==='delete_social_category')return deleteCategory(p,a,args);
 if(name==='update_social_service_content')return updateServiceContent(p,a,args);
 if(name==='list_velixeo_social_services')return listVelixeoServices(p,args);
 if(name==='show_social_structure')return structure(p);
 throw new Error('UNKNOWN_TOOL:'+name);
}
const rpcResult=(id:McpRequest['id'],value:unknown)=>({jsonrpc:'2.0',id:id??null,result:value});
const rpcError=(id:McpRequest['id'],code:number,message:string)=>({jsonrpc:'2.0',id:id??null,error:{code,message}});

async function handleMcp(p:PrismaClient,req:FastifyRequest,rep:FastifyReply){
 if(!await authorized(p,req))return rep.code(401).header('Cache-Control','no-store').send({error:'unauthorized_mcp_connection'});
 const body=(req.body||{}) as McpRequest;
 if(!body||body.jsonrpc!=='2.0'||!body.method)return rep.code(400).send(rpcError(body?.id,-32600,'Invalid Request'));
 if(body.method.startsWith('notifications/'))return rep.code(204).send();
 if(body.method==='initialize'){
  const requested=String((body.params||{}).protocolVersion||''),protocolVersion=PROTOCOLS.includes(requested)?requested:PROTOCOLS[0];
  return rep.send(rpcResult(body.id,{protocolVersion,capabilities:{tools:{listChanged:false}},serverInfo:{name:'VELIXEO AI Agent',version:VERSION},instructions:'Inspect first. Every write requires approval=I_CONFIRM. Never invent a markup percentage; use only the exact percentage supplied by the administrator.'}));
 }
 if(body.method==='ping')return rep.send(rpcResult(body.id,{}));
 if(body.method==='tools/list')return rep.send(rpcResult(body.id,{tools}));
 if(body.method==='tools/call'){
  const params=(body.params||{}) as J,name=String(params.name||''),args=params.arguments&&typeof params.arguments==='object'&&!Array.isArray(params.arguments)?params.arguments as J:{};
  try{return rep.send(rpcResult(body.id,result(await execute(p,await actor(p),name,args))));}
  catch(error){return rep.send(rpcResult(body.id,toolError(error)));}
 }
 return rep.code(404).send(rpcError(body.id,-32601,'Method not found'));
}

function connectorHtml(admin:AdminIdentity,lang:'fa'|'en',baseUrl:string,isConfigured:boolean,token?:string){
 const fa=lang==='fa',endpoint=baseUrl.replace(/\/$/,'')+'/mcp',privateUrl=token?endpoint+'?token='+encodeURIComponent(token):'';
 const body=[
 '<div class="grid eq"><div class="card"><div class="cardhead"><div><h2>',fa?'اتصال VELIXEO به ChatGPT':'Connect VELIXEO to ChatGPT','</h2><span class="muted">',fa?'مدیریت مستقیم VELIXEO از داخل گفتگو':'Manage VELIXEO directly from ChatGPT','</span></div><span class="pill ',isConfigured?'ok':'warn','">',isConfigured?(fa?'فعال':'Ready'):(fa?'تنظیم نشده':'Not configured'),'</span></div>',
 '<div class="notice">',fa?'این بخش مدل AI جدا داخل پنل اجرا نمی‌کند. ChatGPT مستقیماً ابزارهای VELIXEO را صدا می‌زند. عملیات نوشتنی همگی نیاز به تأیید I_CONFIRM دارند.':'This does not run another AI model inside Admin. ChatGPT calls VELIXEO tools directly. Every write requires I_CONFIRM.','</div>',
 token?'<div class="field"><label>'+(fa?'لینک خصوصی اتصال — فقط همین‌بار نمایش داده می‌شود':'Private connection URL — shown only this time')+'</label><textarea class="mono" readonly style="min-height:105px">'+privateUrl+'</textarea></div>':'',
 token?'<div class="notice"><b>'+(fa?'مهم:':'Important:')+'</b> '+(fa?'این لینک را مانند رمز عبور نگهداری کن و برای شخص دیگری نفرست.':'Treat this URL like a password and do not share it.')+'</div>':'',
 '<form method="post" action="/admin/v3/chatgpt-connector/generate"><button class="btn">',isConfigured?(fa?'ساخت لینک جدید و باطل‌کردن قبلی':'Rotate private connection'):(fa?'ساخت لینک اتصال ChatGPT':'Generate ChatGPT connection'),'</button></form></div>',
 '<div class="card"><div class="cardhead"><h2>',fa?'روش استفاده':'How to use it','</h2></div><div class="notice">',fa?'پس از ساخت لینک، در ChatGPT Developer mode یک Plugin/MCP شخصی ایجاد کن و لینک را به‌عنوان MCP Server URL بده. بعد در همین محیط گفتگو می‌توانی به VELIXEO دستور بدهی.':'After generating the link, create a personal Plugin/MCP connection in ChatGPT Developer mode and paste it as the MCP Server URL. Then manage VELIXEO from the conversation.','</div>',
 '<div class="provider"><div><b>MCP endpoint</b><small class="mono">',endpoint,'</small></div><span class="pill info">v',VERSION,'</span></div>',
 '<div class="provider"><div><b>',fa?'ابزارهای اولیه':'Initial tools','</b><small>',fa?'ارائه‌دهنده، برند، دسته، سرویس، سود و Diagnostics':'Providers, brands, categories, services, markup and diagnostics','</small></div><span class="pill ok">',String(tools.length),'</span></div>',
 '<div class="provider"><div><b>',fa?'ویرایش و حذف دسته‌ها':'Category edit & delete','</b><small>',fa?'ویرایش کامل دسته و حذف امن با غیرفعال‌سازی سرویس‌های داخل آن':'Full category editing plus safe deletion that disables assigned services','</small></div><span class="pill ok">',fa?'فعال':'Available','</span></div></div></div>'
 ].join('');
 return renderAdminV3Page(admin,'settings',body,'','',false,lang,fa?'اتصال ChatGPT':'ChatGPT Connector',fa?'مدیریت مستقیم VELIXEO از داخل ChatGPT':'Manage VELIXEO directly from ChatGPT');
}

export function registerVelixeoMcp(app:FastifyInstance,p:PrismaClient,resolveAdmin:AdminResolver){
 app.post('/mcp',async(req,rep)=>handleMcp(p,req,rep));
 app.get('/mcp',async(req,rep)=>{
  if(!await authorized(p,req))return rep.code(401).send({error:'unauthorized_mcp_connection'});
  return rep.header('Cache-Control','no-store').send({name:'VELIXEO AI Agent',version:VERSION,endpoint:'/mcp'});
 });
 app.get('/admin/v3/chatgpt-connector',async(req,rep)=>{
  const admin=await resolveAdmin(req);if(!admin)return rep.code(303).redirect('/admin/login');
  const lang=adminLangFromRequest(req),base=String(process.env.PUBLIC_BASE_URL||'').trim()||(req.protocol+'://'+req.hostname);
  return rep.type('text/html; charset=utf-8').send(connectorHtml(admin,lang,base,Boolean(await savedHash(p))));
 });
 app.post('/admin/v3/chatgpt-connector/generate',async(req,rep)=>{
  const admin=await resolveAdmin(req);if(!admin)return rep.code(303).redirect('/admin/login');
  const lang=adminLangFromRequest(req),token=randomBytes(32).toString('base64url'),value={sha256:hash(token),createdBy:admin.id,createdAt:new Date().toISOString(),version:VERSION};
  await p.systemSetting.upsert({where:{key:TOKEN_KEY},create:{key:TOKEN_KEY,category:'chatgpt-connector',description:'Hashed private token for the VELIXEO ChatGPT MCP connector.',value:value as unknown as Prisma.InputJsonValue},update:{category:'chatgpt-connector',value:value as unknown as Prisma.InputJsonValue}});
  await audit(p,admin,'CHATGPT_CONNECTOR_TOKEN_ROTATE','SystemSetting',null,'Generated or rotated the private VELIXEO ChatGPT connector token');
  const base=String(process.env.PUBLIC_BASE_URL||'').trim()||(req.protocol+'://'+req.hostname);
  return rep.type('text/html; charset=utf-8').send(connectorHtml(admin,lang,base,true,token));
 });
}
