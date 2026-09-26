
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

const VERSION='1.3.0';
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
 return {providerId,brandKey,candidateKey,total:routes.length,offset,limit,hasMore:offset+page.length<routes.length,services:page.map(r=>{const eta=providerStartEtaFromMetadata(r.metadata,r.providerName),avg=providerAverageEtaFromMetadata(r.metadata);return {routeId:r.id,serviceId:r.serviceId,providerServiceId:r.providerServiceCode,providerName:r.providerName||r.service.titleEn,providerCategory:r.providerCategory,providerType:r.providerType,providerRate:r.providerRate?.toString()||null,providerCurrency:r.providerCurrency,min:r.providerMinQty,max:r.providerMaxQty,refill:r.providerRefill,cancel:r.providerCancel,providerStartTime:eta?.text||null,providerStartMinMinutes:eta?.minMinutes??null,providerStartMaxMinutes:eta?.maxMinutes??null,providerAverageTime:avg?.text||null,providerAverageMinMinutes:avg?.minMinutes??null,providerAverageMaxMinutes:avg?.maxMinutes??null,lastSyncedAt:r.lastSyncedAt?.toISOString()||null,markupPercent:r.markupPercent?.toString()??r.provider.defaultMarkupPercent.toString(),alreadyAdded:obj(r.service.metadata).rawCatalog!==true,existingTitleEn:r.service.titleEn,existingTitleFa:r.service.titleFa,existingDescriptionEn:r.service.descriptionEn,existingDescriptionFa:r.service.descriptionFa,providerDescription:(()=>{const m=obj(r.metadata);for(const k of ['description','desc','service_description','serviceDescription','details','note','notes']){const v=m[k];if(v!=null&&String(v).trim())return String(v).trim();}return null;})()};})};
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
 const services=await p.service.findMany({where:{category:ServiceCategory.SOCIAL,socialGroup:slug},select:{id:true}});
 const returnedServiceCount=await returnServicesToProviderCatalog(p,services.map(s=>s.id),'CATEGORY_DELETED');
 await p.systemSetting.delete({where:{key}});
 await audit(p,a,'CHATGPT_SOCIAL_CATEGORY_DELETE','SocialCategory',slug,'ChatGPT deleted the explicitly requested category and returned its services to Provider Services',{slug,returnedServiceCount} as unknown as Prisma.InputJsonValue);
 return {deleted:true,slug,returnedServiceCount};
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
 return {count:rows.length,services:rows.map(service=>({id:service.id,slug:service.slug,titleEn:service.titleEn,titleFa:service.titleFa,descriptionEn:service.descriptionEn,descriptionFa:service.descriptionFa,enabled:service.enabled,featured:service.featured,platform:service.socialPlatform,categorySlug:service.socialGroup,basePriceAfn:service.basePriceAfn?.toString()||null,priceUnit:service.priceUnit,minQty:service.minQty,maxQty:service.maxQty,estimatedMinMinutes:service.estimatedMinMinutes,estimatedMaxMinutes:service.estimatedMaxMinutes,refillDays:service.refillDays,sortOrder:service.sortOrder,pricingMode:String(obj(service.metadata).pricingMode||'AUTO_MARKUP'),routes:service.routes.map(r=>{const eta=providerStartEtaFromMetadata(r.metadata,r.providerName),m=obj(r.metadata);let providerDescription:null|string=null;for(const k of ['description','desc','service_description','serviceDescription','details','note','notes']){const v=m[k];if(v!=null&&String(v).trim()){providerDescription=String(v).trim();break;}}return {routeId:r.id,providerId:r.providerId,providerName:r.provider.name,providerServiceId:r.providerServiceCode,priority:r.priority,routeEnabled:r.enabled,markupPercent:r.markupPercent?.toString()||null,refill:r.providerRefill,cancel:r.providerCancel,providerStartTime:eta?.text||null,providerDescription};})}))};
}


function validateConnectorBrandIcon(type:string,value:string,key:string){
 const t=type.toUpperCase();
 if(t==='DEFAULT'){
  const icon=(value||key.toLowerCase()).trim().toLowerCase();
  return {type:'DEFAULT' as const,value:(defaultBrandIcons as readonly string[]).includes(icon)?icon:'generic'};
 }
 if(t==='URL'){
  const url=new URL(value);
  if(!['https:','http:'].includes(url.protocol))throw new Error('BRAND_ICON_URL_INVALID');
  return {type:'URL' as const,value:url.toString()};
 }
 if(t==='UPLOAD'){
  if(!/^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(value))throw new Error('BRAND_ICON_UPLOAD_INVALID');
  if(value.length>550000)throw new Error('BRAND_ICON_UPLOAD_TOO_LARGE');
  return {type:'UPLOAD' as const,value};
 }
 throw new Error('BRAND_ICON_TYPE_INVALID');
}
async function updateBrand(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const oldKey=normalizeBrandKey(String(args.brand_key||''));if(!oldKey)throw new Error('BRAND_KEY_REQUIRED');
 const brands=await loadSocialBrands(p),current=brands.find(b=>b.key===oldKey);if(!current)throw new Error('SOCIAL_BRAND_NOT_FOUND');
 const newKey=args.new_key!==undefined?normalizeBrandKey(String(args.new_key||'')):oldKey;if(!newKey)throw new Error('NEW_BRAND_KEY_INVALID');
 if(newKey!==oldKey&&brands.some(b=>b.key===newKey))throw new Error('BRAND_KEY_ALREADY_EXISTS');
 const requestedIconType=args.icon_type!==undefined?String(args.icon_type||'').toUpperCase():current.iconType;
 const requestedIconValue=args.icon_value!==undefined?String(args.icon_value||'').trim():current.iconValue;
 const icon=validateConnectorBrandIcon(requestedIconType,requestedIconValue,newKey);
 const value={
  key:newKey,
  titleEn:args.title_en!==undefined?String(args.title_en||'').trim():current.titleEn,
  titleFa:args.title_fa!==undefined?String(args.title_fa||'').trim():current.titleFa,
  iconType:icon.type,
  iconValue:icon.value,
  sortOrder:args.sort_order!==undefined?Math.floor(Number(args.sort_order)):current.sortOrder,
  enabled:args.enabled!==undefined?Boolean(args.enabled):current.enabled
 };
 if(!value.titleEn||!value.titleFa)throw new Error('BILINGUAL_BRAND_TITLES_REQUIRED');
 if(!Number.isFinite(value.sortOrder))throw new Error('BRAND_SORT_ORDER_INVALID');
 const categoryRows=await p.systemSetting.findMany({where:{category:'social-category'}});
 const affected=categoryRows.filter(row=>normalizeBrandKey(String(obj(row.value).platform||''))===oldKey);
 await p.$transaction(async tx=>{
  await tx.systemSetting.upsert({
   where:{key:brandSettingKey(newKey)},
   create:{key:brandSettingKey(newKey),category:'social-brand',description:'Social Media customer-facing brand.',value:value as unknown as Prisma.InputJsonValue},
   update:{category:'social-brand',value:value as unknown as Prisma.InputJsonValue}
  });
  if(newKey!==oldKey){
   for(const row of affected){
    const next={...obj(row.value),platform:newKey};
    await tx.systemSetting.update({where:{key:row.key},data:{value:next as Prisma.InputJsonValue}});
   }
   await tx.service.updateMany({where:{category:ServiceCategory.SOCIAL,socialPlatform:oldKey},data:{socialPlatform:newKey}});
   await tx.systemSetting.deleteMany({where:{key:brandSettingKey(oldKey)}});
  }
 });
 await audit(p,a,'CHATGPT_SOCIAL_BRAND_UPDATE','SocialBrand',newKey,'ChatGPT updated social brand only as explicitly requested',{oldKey,newKey,categoryCount:affected.length} as unknown as Prisma.InputJsonValue);
 return {oldKey,renamed:newKey!==oldKey,...value,affectedCategories:affected.length};
}
async function returnServicesToProviderCatalog(p:PrismaClient,serviceIds:string[],reason:string){
 let changed=0;
 for(const id of serviceIds){
  const service=await p.service.findUnique({where:{id},select:{id:true,metadata:true}});
  if(!service)continue;
  const meta=obj(service.metadata);
  await p.service.update({where:{id},data:{
   enabled:false,
   basePriceAfn:null,
   socialPlatform:null,
   socialGroup:null,
   metadata:{...meta,rawCatalog:true,addedToVelixeo:false,pricingMode:'AUTO_MARKUP',categorySlug:null,removedFromVelixeoAt:new Date().toISOString(),removedFromVelixeoReason:reason,managedByChatGPT:true} as Prisma.InputJsonValue
  }});
  changed++;
 }
 return changed;
}
async function deleteBrand(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const brandKey=normalizeBrandKey(String(args.brand_key||''));if(!brandKey)throw new Error('BRAND_KEY_REQUIRED');
 const brands=await loadSocialBrands(p);if(!brands.some(b=>b.key===brandKey))throw new Error('SOCIAL_BRAND_NOT_FOUND');
 const cats=(await categories(p)).filter(cat=>cat.platform===brandKey),slugs=cats.map(cat=>cat.slug);
 const services=await p.service.findMany({where:{category:ServiceCategory.SOCIAL,OR:[
  {socialPlatform:brandKey},
  ...(slugs.length?[{socialGroup:{in:slugs}}]:[])
 ]},select:{id:true}});
 const ids=[...new Set(services.map(s=>s.id))];
 const unpublished=await returnServicesToProviderCatalog(p,ids,'BRAND_DELETED');
 await p.$transaction([
  ...(slugs.length?[p.systemSetting.deleteMany({where:{key:{in:slugs.map(catKey)}}})]:[]),
  p.systemSetting.deleteMany({where:{key:brandSettingKey(brandKey)}})
 ]);
 await audit(p,a,'CHATGPT_SOCIAL_BRAND_DELETE','SocialBrand',brandKey,'ChatGPT deleted the explicitly requested social brand and returned its services to Provider Services',{brandKey,categoryCount:cats.length,unpublishedServices:unpublished} as unknown as Prisma.InputJsonValue);
 return {deleted:true,brandKey,deletedCategories:cats.length,returnedServices:unpublished};
}
async function updateService(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const serviceId=String(args.service_id||'').trim();if(!serviceId)throw new Error('SERVICE_ID_REQUIRED');
 const service=await p.service.findFirst({where:{id:serviceId,category:ServiceCategory.SOCIAL}});if(!service)throw new Error('SOCIAL_SERVICE_NOT_FOUND');
 if(obj(service.metadata).rawCatalog===true)throw new Error('SERVICE_NOT_PUBLISHED_TO_VELIXEO');
 const data:Prisma.ServiceUpdateInput={};
 let targetCategory:{slug:string;platform:string}|null=null;
 if(args.category_slug!==undefined){
  const slug=safeSlug(String(args.category_slug||''));if(!slug)throw new Error('CATEGORY_SLUG_REQUIRED');
  const cat=(await categories(p)).find(x=>x.slug===slug);if(!cat)throw new Error('CATEGORY_NOT_FOUND');
  targetCategory={slug:cat.slug,platform:cat.platform};
  data.socialGroup=cat.slug;data.socialPlatform=cat.platform;
 }
 if(args.title_en!==undefined){const v=String(args.title_en||'').trim();if(!v)throw new Error('TITLE_EN_REQUIRED');data.titleEn=v;}
 if(args.title_fa!==undefined){const v=String(args.title_fa||'').trim();if(!v)throw new Error('TITLE_FA_REQUIRED');data.titleFa=v;}
 if(args.description_en!==undefined)data.descriptionEn=String(args.description_en||'').trim()||null;
 if(args.description_fa!==undefined)data.descriptionFa=String(args.description_fa||'').trim()||null;
 const numeric=(name:string,min:number|null=0)=>{
  if(args[name]===undefined)return undefined;
  const n=Number(args[name]);if(!Number.isFinite(n)||!Number.isInteger(n)||(min!==null&&n<min))throw new Error(name.toUpperCase()+'_INVALID');
  return n;
 };
 const minQty=numeric('min_qty',1),maxQty=numeric('max_qty',1),minEta=numeric('estimated_min_minutes',0),maxEta=numeric('estimated_max_minutes',0),refillDays=numeric('refill_days',0),sortOrder=numeric('sort_order',null),priceUnit=numeric('price_unit',1);
 if(args.clear_min_qty===true)data.minQty=null;else if(minQty!==undefined)data.minQty=minQty;
 if(args.clear_max_qty===true)data.maxQty=null;else if(maxQty!==undefined)data.maxQty=maxQty;
 const nextMin=args.clear_min_qty===true?null:(minQty??service.minQty),nextMax=args.clear_max_qty===true?null:(maxQty??service.maxQty);
 if(nextMin!=null&&nextMax!=null&&nextMin>nextMax)throw new Error('MIN_MAX_INVALID');
 if(args.clear_estimated_min_minutes===true)data.estimatedMinMinutes=null;else if(minEta!==undefined)data.estimatedMinMinutes=minEta;
 if(args.clear_estimated_max_minutes===true)data.estimatedMaxMinutes=null;else if(maxEta!==undefined)data.estimatedMaxMinutes=maxEta;
 const nextMinEta=args.clear_estimated_min_minutes===true?null:(minEta??service.estimatedMinMinutes),nextMaxEta=args.clear_estimated_max_minutes===true?null:(maxEta??service.estimatedMaxMinutes);
 if(nextMinEta!=null&&nextMaxEta!=null&&nextMinEta>nextMaxEta)throw new Error('ETA_INVALID');
 if(args.clear_refill_days===true)data.refillDays=null;else if(refillDays!==undefined)data.refillDays=refillDays;
 if(sortOrder!==undefined)data.sortOrder=sortOrder;
 if(priceUnit!==undefined)data.priceUnit=priceUnit;
 if(args.enabled!==undefined)data.enabled=Boolean(args.enabled);
 if(args.featured!==undefined)data.featured=Boolean(args.featured);
 if(targetCategory){
  data.metadata={...obj(service.metadata),rawCatalog:false,addedToVelixeo:true,categorySlug:targetCategory.slug,managedByChatGPT:true} as Prisma.InputJsonValue;
 }
 const saved=await p.service.update({where:{id:serviceId},data});
 await audit(p,a,'CHATGPT_SOCIAL_SERVICE_UPDATE','Service',serviceId,'ChatGPT updated only the explicitly requested service fields',{serviceId,categorySlug:targetCategory?.slug||null,changedFields:Object.keys(data)} as unknown as Prisma.InputJsonValue);
 return {serviceId,titleEn:saved.titleEn,titleFa:saved.titleFa,descriptionEn:saved.descriptionEn,descriptionFa:saved.descriptionFa,platform:saved.socialPlatform,categorySlug:saved.socialGroup,enabled:saved.enabled,featured:saved.featured,minQty:saved.minQty,maxQty:saved.maxQty,estimatedMinMinutes:saved.estimatedMinMinutes,estimatedMaxMinutes:saved.estimatedMaxMinutes,refillDays:saved.refillDays,sortOrder:saved.sortOrder,priceUnit:saved.priceUnit};
}
async function fixedPriceAfn(p:PrismaClient,amountRaw:unknown,currencyRaw:unknown){
 const amount=new Prisma.Decimal(String(amountRaw??''));
 if(!amount.isFinite()||amount.lte(0))throw new Error('FIXED_PRICE_INVALID');
 const currency=String(currencyRaw||'').trim().toUpperCase();if(!currency)throw new Error('FIXED_CURRENCY_REQUIRED');
 if(currency==='AFN')return {afn:BigInt(amount.ceil().toFixed(0)),currency,amount:amount.toString()};
 const rate=await p.exchangeRate.findUnique({where:{code:currency}});if(!rate)throw new Error('EXCHANGE_RATE_NOT_FOUND:'+currency);
 const afn=amount.mul(rate.afnPerUnit);
 return {afn:BigInt(afn.ceil().toFixed(0)),currency,amount:amount.toString()};
}
async function setServicePricing(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const serviceId=String(args.service_id||'').trim(),mode=String(args.pricing_mode||'').trim().toUpperCase();
 if(!serviceId)throw new Error('SERVICE_ID_REQUIRED');
 const service=await p.service.findFirst({where:{id:serviceId,category:ServiceCategory.SOCIAL},include:{routes:true}});if(!service)throw new Error('SOCIAL_SERVICE_NOT_FOUND');
 if(obj(service.metadata).rawCatalog===true)throw new Error('SERVICE_NOT_PUBLISHED_TO_VELIXEO');
 if(mode!=='AUTO_MARKUP'&&mode!=='FIXED')throw new Error('PRICING_MODE_REQUIRED');
 let basePriceAfn:bigint|null=null,markupPercent:number|null=null,fixedOriginal:J|null=null;
 if(mode==='AUTO_MARKUP'){
  const markup=Number(args.markup_percent);if(!Number.isFinite(markup)||markup<0||markup>1000)throw new Error('MARKUP_PERCENT_REQUIRED_EXACT');
  markupPercent=markup;
  await p.serviceProviderRoute.updateMany({where:{serviceId},data:{markupPercent:new Prisma.Decimal(markup)}});
 }else{
  const fixed=await fixedPriceAfn(p,args.fixed_price,args.fixed_currency);basePriceAfn=fixed.afn;fixedOriginal={amount:fixed.amount,currency:fixed.currency};
  await p.serviceProviderRoute.updateMany({where:{serviceId},data:{markupPercent:null}});
 }
 const meta={...obj(service.metadata),pricingMode:mode,managedByChatGPT:true,...(fixedOriginal?{fixedPriceOriginal:fixedOriginal}:{fixedPriceOriginal:null})};
 const priceUnit=args.price_unit!==undefined?Number(args.price_unit):service.priceUnit;
 if(!Number.isFinite(priceUnit)||!Number.isInteger(priceUnit)||priceUnit<1)throw new Error('PRICE_UNIT_INVALID');
 const saved=await p.service.update({where:{id:serviceId},data:{basePriceAfn,priceUnit,metadata:meta as Prisma.InputJsonValue}});
 await audit(p,a,'CHATGPT_SOCIAL_SERVICE_PRICING','Service',serviceId,'ChatGPT applied only the exact administrator-specified pricing',{serviceId,mode,markupPercent,fixedOriginal,basePriceAfn:basePriceAfn?.toString()||null,priceUnit} as unknown as Prisma.InputJsonValue);
 return {serviceId,pricingMode:mode,markupPercent,fixedPriceAfn:saved.basePriceAfn?.toString()||null,fixedOriginal,priceUnit:saved.priceUnit,affectedRoutes:service.routes.length};
}
async function updateRoute(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const routeId=String(args.route_id||'').trim();if(!routeId)throw new Error('ROUTE_ID_REQUIRED');
 const route=await p.serviceProviderRoute.findUnique({where:{id:routeId}});if(!route)throw new Error('SOCIAL_ROUTE_NOT_FOUND');
 const data:Prisma.ServiceProviderRouteUpdateInput={};
 if(args.priority!==undefined){const n=Number(args.priority);if(!Number.isFinite(n)||!Number.isInteger(n))throw new Error('ROUTE_PRIORITY_INVALID');data.priority=n;}
 if(args.enabled!==undefined)data.enabled=Boolean(args.enabled);
 if(args.use_provider_default_markup===true&&args.markup_percent!==undefined)throw new Error('CHOOSE_EXACT_MARKUP_OR_PROVIDER_DEFAULT');
 if(args.use_provider_default_markup===true)data.markupPercent=null;
 else if(args.markup_percent!==undefined){
  const n=Number(args.markup_percent);if(!Number.isFinite(n)||n<0||n>1000)throw new Error('MARKUP_PERCENT_OUT_OF_RANGE');
  data.markupPercent=new Prisma.Decimal(n);
 }
 if(!Object.keys(data).length)throw new Error('NO_ROUTE_CHANGES_REQUESTED');
 const saved=await p.serviceProviderRoute.update({where:{id:routeId},data});
 await audit(p,a,'CHATGPT_SOCIAL_ROUTE_UPDATE','ServiceProviderRoute',routeId,'ChatGPT updated only the explicitly requested route fields',{routeId,changedFields:Object.keys(data)} as unknown as Prisma.InputJsonValue);
 return {routeId,serviceId:saved.serviceId,providerId:saved.providerId,priority:saved.priority,enabled:saved.enabled,markupPercent:saved.markupPercent?.toString()||null};
}
async function removeService(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const serviceId=String(args.service_id||'').trim();if(!serviceId)throw new Error('SERVICE_ID_REQUIRED');
 const service=await p.service.findFirst({where:{id:serviceId,category:ServiceCategory.SOCIAL}});if(!service)throw new Error('SOCIAL_SERVICE_NOT_FOUND');
 if(obj(service.metadata).rawCatalog===true)throw new Error('SERVICE_ALREADY_IN_PROVIDER_CATALOG');
 const count=await returnServicesToProviderCatalog(p,[serviceId],'SERVICE_REMOVED');
 await audit(p,a,'CHATGPT_SOCIAL_SERVICE_REMOVE','Service',serviceId,'ChatGPT removed the explicitly requested service from VELIXEO and kept the provider route',{serviceId} as unknown as Prisma.InputJsonValue);
 return {removed:count===1,serviceId,returnedToProviderServices:true};
}
async function bulkUpdateContent(p:PrismaClient,a:AdminIdentity,args:J){
 needApproval(args);
 const categoryRows=Array.isArray(args.categories)?args.categories:[],serviceRows=Array.isArray(args.services)?args.services:[];
 if(!categoryRows.length&&!serviceRows.length)throw new Error('CONTENT_ITEMS_REQUIRED');
 if(categoryRows.length>200||serviceRows.length>500)throw new Error('CONTENT_BATCH_TOO_LARGE');
 const categoriesSaved=[] as J[],servicesSaved=[] as J[];
 for(const item of categoryRows){
  if(!item||typeof item!=='object'||Array.isArray(item))continue;
  const row=item as J,slug=safeSlug(String(row.category_slug||''));if(!slug)throw new Error('CATEGORY_SLUG_REQUIRED');
  const key=catKey(slug),setting=await p.systemSetting.findUnique({where:{key}});if(!setting)throw new Error('CATEGORY_NOT_FOUND:'+slug);
  const value=obj(setting.value),next={...value,
   ...(row.title_en!==undefined?{titleEn:String(row.title_en||'').trim()}:{ }),
   ...(row.title_fa!==undefined?{titleFa:String(row.title_fa||'').trim()}:{ }),
   ...(row.description_en!==undefined?{descriptionEn:String(row.description_en||'').trim()}:{ }),
   ...(row.description_fa!==undefined?{descriptionFa:String(row.description_fa||'').trim()}:{ })
  };
  if(!String(next.titleEn||'').trim()||!String(next.titleFa||'').trim())throw new Error('BILINGUAL_CATEGORY_TITLES_REQUIRED:'+slug);
  await p.systemSetting.update({where:{key},data:{value:next as Prisma.InputJsonValue}});
  categoriesSaved.push({categorySlug:slug,titleEn:next.titleEn,titleFa:next.titleFa,descriptionEn:next.descriptionEn||'',descriptionFa:next.descriptionFa||''});
 }
 for(const item of serviceRows){
  if(!item||typeof item!=='object'||Array.isArray(item))continue;
  const row=item as J,serviceId=String(row.service_id||'').trim();if(!serviceId)throw new Error('SERVICE_ID_REQUIRED');
  const service=await p.service.findFirst({where:{id:serviceId,category:ServiceCategory.SOCIAL}});if(!service)throw new Error('SOCIAL_SERVICE_NOT_FOUND:'+serviceId);
  const data:Prisma.ServiceUpdateInput={};
  if(row.title_en!==undefined){const v=String(row.title_en||'').trim();if(!v)throw new Error('TITLE_EN_REQUIRED:'+serviceId);data.titleEn=v;}
  if(row.title_fa!==undefined){const v=String(row.title_fa||'').trim();if(!v)throw new Error('TITLE_FA_REQUIRED:'+serviceId);data.titleFa=v;}
  if(row.description_en!==undefined)data.descriptionEn=String(row.description_en||'').trim()||null;
  if(row.description_fa!==undefined)data.descriptionFa=String(row.description_fa||'').trim()||null;
  if(!Object.keys(data).length)throw new Error('NO_CONTENT_CHANGES:'+serviceId);
  const saved=await p.service.update({where:{id:serviceId},data});
  servicesSaved.push({serviceId,titleEn:saved.titleEn,titleFa:saved.titleFa,descriptionEn:saved.descriptionEn,descriptionFa:saved.descriptionFa});
 }
 await audit(p,a,'CHATGPT_SOCIAL_BULK_CONTENT_UPDATE','SocialContent',null,'ChatGPT applied the explicitly approved bilingual content batch',{categoryCount:categoriesSaved.length,serviceCount:servicesSaved.length} as unknown as Prisma.InputJsonValue);
 return {categoryCount:categoriesSaved.length,serviceCount:servicesSaved.length,categories:categoriesSaved,services:servicesSaved};
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
 {name:'update_social_brand',description:'Edit an existing Social Media brand: key, bilingual names, icon, display order or visibility. Change only fields explicitly provided by the administrator. Requires explicit approval.',inputSchema:{type:'object',properties:{brand_key:{type:'string'},new_key:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},icon_type:{type:'string',enum:['DEFAULT','URL','UPLOAD']},icon_value:{type:'string'},sort_order:{type:'integer'},enabled:{type:'boolean'},approval:{type:'string',enum:[APPROVAL]}},required:['brand_key','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'delete_social_brand',description:'Delete exactly the requested Social Media brand, delete its categories, and safely return its published services to Provider Services. Requires explicit approval.',inputSchema:{type:'object',properties:{brand_key:{type:'string'},approval:{type:'string',enum:[APPROVAL]}},required:['brand_key','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:true}},
 {name:'update_social_service',description:'Edit exactly the requested existing VELIXEO Social Media service: move category, bilingual title/description, min/max, ETA, refill days, price unit, display order, enabled or featured. Does not change pricing markup unless set_social_service_pricing is called. Requires explicit approval.',inputSchema:{type:'object',properties:{service_id:{type:'string'},category_slug:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'},min_qty:{type:'integer',minimum:1},max_qty:{type:'integer',minimum:1},clear_min_qty:{type:'boolean'},clear_max_qty:{type:'boolean'},estimated_min_minutes:{type:'integer',minimum:0},estimated_max_minutes:{type:'integer',minimum:0},clear_estimated_min_minutes:{type:'boolean'},clear_estimated_max_minutes:{type:'boolean'},refill_days:{type:'integer',minimum:0},clear_refill_days:{type:'boolean'},price_unit:{type:'integer',minimum:1},sort_order:{type:'integer'},enabled:{type:'boolean'},featured:{type:'boolean'},approval:{type:'string',enum:[APPROVAL]}},required:['service_id','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'set_social_service_pricing',description:'Set exact pricing for one existing VELIXEO Social Media service. AUTO_MARKUP requires an exact markup_percent supplied by the administrator. FIXED requires exact fixed_price and fixed_currency. Never infer pricing. Requires explicit approval.',inputSchema:{type:'object',properties:{service_id:{type:'string'},pricing_mode:{type:'string',enum:['AUTO_MARKUP','FIXED']},markup_percent:{type:'number',minimum:0,maximum:1000},fixed_price:{type:'number',exclusiveMinimum:0},fixed_currency:{type:'string'},price_unit:{type:'integer',minimum:1},approval:{type:'string',enum:[APPROVAL]}},required:['service_id','pricing_mode','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'update_social_route',description:'Edit exactly one provider route: priority, enabled state, or exact markup. To inherit provider default markup set use_provider_default_markup=true. Requires explicit approval.',inputSchema:{type:'object',properties:{route_id:{type:'string'},priority:{type:'integer'},enabled:{type:'boolean'},markup_percent:{type:'number',minimum:0,maximum:1000},use_provider_default_markup:{type:'boolean'},approval:{type:'string',enum:[APPROVAL]}},required:['route_id','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
 {name:'remove_social_service',description:'Remove exactly one published Social Media service from VELIXEO and return it to Provider Services while retaining its provider route. Requires explicit approval.',inputSchema:{type:'object',properties:{service_id:{type:'string'},approval:{type:'string',enum:[APPROVAL]}},required:['service_id','approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:true}},
 {name:'bulk_update_social_content',description:'Apply an explicitly approved batch of bilingual titles/descriptions to existing Social Media categories/services. Changes only content fields supplied in the request. Requires explicit approval.',inputSchema:{type:'object',properties:{categories:{type:'array',maxItems:200,items:{type:'object',properties:{category_slug:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'}},required:['category_slug'],additionalProperties:false}},services:{type:'array',maxItems:500,items:{type:'object',properties:{service_id:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'},description_en:{type:'string'},description_fa:{type:'string'}},required:['service_id'],additionalProperties:false}},approval:{type:'string',enum:[APPROVAL]}},required:['approval'],additionalProperties:false},annotations:{readOnlyHint:false,destructiveHint:false}},
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
 if(name==='update_social_brand')return updateBrand(p,a,args);
 if(name==='delete_social_brand')return deleteBrand(p,a,args);
 if(name==='update_social_service')return updateService(p,a,args);
 if(name==='set_social_service_pricing')return setServicePricing(p,a,args);
 if(name==='update_social_route')return updateRoute(p,a,args);
 if(name==='remove_social_service')return removeService(p,a,args);
 if(name==='bulk_update_social_content')return bulkUpdateContent(p,a,args);
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
  return rep.send(rpcResult(body.id,{protocolVersion,capabilities:{tools:{listChanged:true}},serverInfo:{name:'VELIXEO AI Agent',version:VERSION},instructions:'Inspect first. NEVER make any write, cleanup, migration, pricing, move, delete, create, rename, enable/disable, or content change unless the administrator explicitly requested that exact action and supplied approval=I_CONFIRM. Do not infer adjacent changes or improve anything on your own. Execute only the requested scope. Never invent a markup, fixed price, currency, destination category, title, description, or deletion target. Read-only inspection may be used to identify exact IDs and current state before asking for approval.'}));
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
 '<div class="notice">',fa?'این بخش مدل AI جدا داخل پنل اجرا نمی‌کند. ChatGPT مستقیماً ابزارهای VELIXEO را صدا می‌زند. ابزار می‌تواند برند، دسته، سرویس، انتقال، قیمت، سود، وضعیت و توضیحات را مدیریت کند؛ اما هیچ تغییری بدون دستور صریح شما و I_CONFIRM انجام نمی‌دهد.':'This does not run another AI model inside Admin. ChatGPT can manage brands, categories, services, moves, pricing, markup, status and descriptions, but it must not make any change without your explicit instruction and I_CONFIRM.','</div>',
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
