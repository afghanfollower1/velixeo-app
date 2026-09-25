
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { Prisma, PrismaClient, ProviderKind, ServiceCategory } from '@prisma/client';
import { brandSettingKey, defaultBrandIcons, loadSocialBrands, normalizeBrandKey } from './socialBrands.js';
import { inferSocialGroup, inferSocialPlatform, syncSocialProviderCatalog } from './socialSync.js';
import { adminLangFromRequest, type AdminLang } from './adminLocale.js';
import { renderAdminV3Page } from './adminFigmaEnglish.js';

type AdminIdentity = { id:string; fullName:string|null; email:string|null; phone:string|null };
type AdminResolver = (request:FastifyRequest)=>Promise<AdminIdentity|null>;
type AgentContext = { prisma:PrismaClient; admin:AdminIdentity; lang:AdminLang; allowWrites:boolean };
type AgentMessage = { role:'user'|'assistant'; text:string; at:string };
type AgentState = { previousResponseId:string|null; messages:AgentMessage[] };
type CategoryRow = { slug:string; titleEn:string; titleFa:string; platform:string; sortOrder:number; enabled:boolean; candidateKey:string };
type AiItem = { type?:string; call_id?:string; name?:string; arguments?:string; content?:Array<{type?:string;text?:string}> };
type AiResponse = { id?:string; output?:AiItem[]; output_text?:string; error?:{message?:string} };

const STATE_PREFIX='admin.ai.state.';
const MODEL_DEFAULT='gpt-5.6-luna';
const brandNames:Record<string,{en:string;fa:string;icon:string}>={
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
  SOUNDCLOUD:{en:'SoundCloud',fa:'ساندکلاد',icon:'soundcloud'},
};
const categoryNames:Record<string,{en:string;fa:string}>={
  FOLLOWERS:{en:'Followers',fa:'فالوور'},
  FOLLOWERS_REFILL:{en:'Followers with Refill',fa:'فالوور با جبران'},
  FOLLOWERS_NO_REFILL:{en:'Followers without Refill',fa:'فالوور بدون جبران'},
  LIKES:{en:'Likes',fa:'لایک'},
  VIEWS:{en:'Views',fa:'بازدید'},
  COMMENTS:{en:'Comments',fa:'کامنت'},
  CUSTOM_COMMENTS:{en:'Custom Comments',fa:'کامنت دلخواه'},
  SHARES:{en:'Shares',fa:'اشتراک‌گذاری'},
  SAVES:{en:'Saves',fa:'ذخیره'},
  REACH:{en:'Reach & Impressions',fa:'ریچ و ایمپرشن'},
  POLL:{en:'Poll & Votes',fa:'نظرسنجی و رأی'},
  TRAFFIC:{en:'Traffic',fa:'ترافیک'},
  OTHER:{en:'Other',fa:'سایر'},
};

const obj=(value:Prisma.JsonValue|null|undefined):Record<string,unknown> =>
  value && typeof value==='object' && !Array.isArray(value) ? value as Record<string,unknown> : {};
const esc=(value:unknown)=>String(value??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');
const normalizeCandidate=(value:string)=>value.trim().toUpperCase().replace(/[^A-Z0-9_]+/g,'_').replace(/^_+|_+$/g,'');
const safeSlug=(value:string)=>value.trim().toLowerCase().replace(/\s+/g,'-').replace(/[^a-z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').slice(0,80);
const titleCase=(value:string)=>value.toLowerCase().split(/[_\s-]+/).filter(Boolean).map(p=>p.charAt(0).toUpperCase()+p.slice(1)).join(' ');
const model=()=>String(process.env.VELIXEO_AI_MODEL||MODEL_DEFAULT).trim()||MODEL_DEFAULT;
const configured=()=>Boolean(String(process.env.OPENAI_API_KEY||'').trim());
const stateKey=(adminId:string)=>STATE_PREFIX+adminId;
const categoryKey=(slug:string)=>'social.category.'+slug;
const explicitWrite=(text:string)=>/(ایجاد|بساز|ساخت|اضافه|اد\s*کن|اجرا|اعمال|بگذار|قرار\s*بده|تنظیم|سود|ذخیره|create|add|apply|execute|set|save|make)/iu.test(text);

function brandLabel(key:string){
  const k=normalizeBrandKey(key);
  return brandNames[k]||{en:titleCase(k||'OTHER'),fa:titleCase(k||'OTHER'),icon:(defaultBrandIcons as readonly string[]).includes(k.toLowerCase())?k.toLowerCase():'generic'};
}
function categoryLabel(key:string){
  const k=normalizeCandidate(key);
  return categoryNames[k]||{en:titleCase(k||'OTHER'),fa:titleCase(k||'OTHER')};
}
function fallbackPersianTitle(title:string){
  const pairs:Array<[RegExp,string]>=[
    [/\bInstagram\b/gi,'اینستاگرام'],[/\bFacebook\b/gi,'فیسبوک'],[/\bTik\s*Tok\b/gi,'تیک‌تاک'],[/\bYouTube\b/gi,'یوتیوب'],[/\bTelegram\b/gi,'تلگرام'],[/\bWhatsApp\b/gi,'واتساپ'],
    [/\bFollowers?\b/gi,'فالوور'],[/\bSubscribers?\b/gi,'سابسکرایبر'],[/\bMembers?\b/gi,'ممبر'],[/\bLikes?\b/gi,'لایک'],[/\bViews?\b/gi,'بازدید'],[/\bComments?\b/gi,'کامنت'],
    [/\bCustom\b/gi,'دلخواه'],[/\bShares?\b/gi,'اشتراک‌گذاری'],[/\bSaves?\b/gi,'ذخیره'],[/\bRefill\b/gi,'جبران'],[/\bNo\s*Refill\b/gi,'بدون جبران'],
    [/\bFast\b/gi,'سریع'],[/\bSlow\b/gi,'آهسته'],[/\bHigh\s*Quality\b/gi,'کیفیت بالا'],[/\bHQ\b/gi,'کیفیت بالا'],[/\bDays?\b/gi,'روز'],
  ];
  let value=title;
  for(const pair of pairs)value=value.replace(pair[0],pair[1]);
  return value.replace(/\s+/g,' ').trim();
}
function routePlatform(route:{providerName:string|null;providerCategory:string|null;service:{titleEn:string;socialPlatform:string|null}}){
  const existing=normalizeBrandKey(route.service.socialPlatform||'');
  if(existing&&existing!=='OTHER')return existing;
  return normalizeBrandKey(inferSocialPlatform([route.providerName,route.providerCategory,route.service.titleEn].filter(Boolean).join(' ')))||'OTHER';
}
function routeCandidate(route:{providerName:string|null;providerType:string|null;providerCategory:string|null;providerRefill:boolean;service:{titleEn:string;socialGroup:string|null}}){
  const joined=[route.providerName,route.providerType,route.providerCategory,route.service.titleEn].filter(Boolean).join(' ');
  if(/custom\s*comments?|comments?\s*custom/i.test(joined))return 'CUSTOM_COMMENTS';
  const inferred=normalizeCandidate(inferSocialGroup(joined));
  if(inferred==='FOLLOWERS')return route.providerRefill?'FOLLOWERS_REFILL':'FOLLOWERS_NO_REFILL';
  return inferred||'OTHER';
}

async function stateRead(prisma:PrismaClient,adminId:string):Promise<AgentState>{
  const row=await prisma.systemSetting.findUnique({where:{key:stateKey(adminId)}});
  const value=obj(row?.value);
  const messages=Array.isArray(value.messages)?value.messages.filter(v=>v&&typeof v==='object'&&!Array.isArray(v)).map(v=>{
    const item=v as Record<string,unknown>;
    return {role:item.role==='assistant'?'assistant' as const:'user' as const,text:String(item.text||''),at:String(item.at||new Date().toISOString())};
  }).filter(v=>v.text).slice(-30):[];
  return {previousResponseId:typeof value.previousResponseId==='string'?value.previousResponseId:null,messages};
}
async function stateSave(prisma:PrismaClient,adminId:string,state:AgentState){
  const value={previousResponseId:state.previousResponseId,messages:state.messages.slice(-30)} as unknown as Prisma.InputJsonValue;
  await prisma.systemSetting.upsert({
    where:{key:stateKey(adminId)},
    create:{key:stateKey(adminId),category:'admin-ai-agent',description:'VELIXEO Admin AI conversation state.',value},
    update:{category:'admin-ai-agent',value},
  });
}
async function audit(ctx:AgentContext,action:string,entityType:string,entityId:string|null,summary:string,metadata?:Prisma.InputJsonValue){
  await ctx.prisma.adminAuditLog.create({data:{adminUserId:ctx.admin.id,action,entityType,entityId,summary,metadata}});
}
function requireWrite(ctx:AgentContext){
  if(ctx.allowWrites)return;
  throw new Error(ctx.lang==='fa'?'برای تغییر اطلاعات باید صریحاً بگویی ایجاد کن، اضافه کن، اعمال کن یا تنظیم کن.':'Explicitly say create, add, apply, set, save, or execute before changing data.');
}
async function categories(prisma:PrismaClient):Promise<CategoryRow[]>{
  const rows=await prisma.systemSetting.findMany({where:{category:'social-category'},orderBy:{key:'asc'}});
  return rows.map(setting=>{
    const v=obj(setting.value),slug=String(v.slug||setting.key.replace(/^social\.category\./,''));
    return {slug,titleEn:String(v.titleEn||slug),titleFa:String(v.titleFa||v.titleEn||slug),platform:normalizeBrandKey(String(v.platform||'OTHER'))||'OTHER',sortOrder:Number(v.sortOrder||100),enabled:v.enabled!==false,candidateKey:normalizeCandidate(String(v.aiCandidateKey||v.sourceCandidateKey||slug))};
  });
}
async function routes(prisma:PrismaClient,providerId:string){
  return prisma.serviceProviderRoute.findMany({
    where:{providerId,provider:{kind:ProviderKind.SOCIAL},service:{category:ServiceCategory.SOCIAL}},
    include:{provider:true,service:true},
    orderBy:[{providerServiceCode:'asc'}],
  });
}
async function toolProviders(ctx:AgentContext){
  const providers=await ctx.prisma.provider.findMany({where:{kind:ProviderKind.SOCIAL},orderBy:[{enabled:'desc'},{priority:'asc'},{name:'asc'}],select:{id:true,name:true,slug:true,enabled:true,currencyCode:true}});
  const result=[];
  for(const provider of providers){
    result.push({...provider,serviceCount:await ctx.prisma.serviceProviderRoute.count({where:{providerId:provider.id}})});
  }
  return {providers:result};
}
async function toolSync(ctx:AgentContext,args:Record<string,unknown>){
  requireWrite(ctx);
  const providerId=String(args.provider_id||'');
  const result=await syncSocialProviderCatalog(ctx.prisma,providerId);
  await audit(ctx,'ADMIN_AI_PROVIDER_SYNC','Provider',providerId,'Admin AI synchronized '+result.total+' social services',result as unknown as Prisma.InputJsonValue);
  return result;
}
async function toolDiscoverBrands(ctx:AgentContext,args:Record<string,unknown>){
  const providerId=String(args.provider_id||''),list=await routes(ctx.prisma,providerId);
  const map=new Map<string,{count:number;examples:string[]}>();
  for(const route of list){
    const key=routePlatform(route);if(key==='OTHER')continue;
    const current=map.get(key)||{count:0,examples:[]};current.count++;
    if(current.examples.length<3)current.examples.push(route.providerName||route.service.titleEn);
    map.set(key,current);
  }
  const existing=new Set((await loadSocialBrands(ctx.prisma)).map(v=>v.key));
  return {providerId,totalServices:list.length,brands:[...map.entries()].map(([key,v])=>({key,titleEn:brandLabel(key).en,titleFa:brandLabel(key).fa,serviceCount:v.count,alreadyCreated:existing.has(key),examples:v.examples})).sort((a,b)=>b.serviceCount-a.serviceCount)};
}
async function toolCreateBrands(ctx:AgentContext,args:Record<string,unknown>){
  requireWrite(ctx);
  const providerId=String(args.provider_id||''),requested=Array.isArray(args.brand_keys)?args.brand_keys.map(v=>normalizeBrandKey(String(v))).filter(Boolean):[];
  const keys=[...new Set(requested)];if(!keys.length)throw new Error('No brand keys supplied.');
  const existing=await loadSocialBrands(ctx.prisma);let order=Math.max(0,...existing.map(v=>v.sortOrder))+10;
  const saved=[];
  for(const key of keys){
    const label=brandLabel(key),settingKey=brandSettingKey(key),old=await ctx.prisma.systemSetting.findUnique({where:{key:settingKey}});
    const value={key,titleEn:label.en,titleFa:label.fa,iconType:'DEFAULT',iconValue:label.icon,sortOrder:old?Number(obj(old.value).sortOrder||order):order,enabled:true,sourceProviderId:providerId,createdByAdminAi:true};
    await ctx.prisma.systemSetting.upsert({where:{key:settingKey},create:{key:settingKey,category:'social-brand',description:'Social Media customer-facing brand.',value:value as unknown as Prisma.InputJsonValue},update:{category:'social-brand',value:value as unknown as Prisma.InputJsonValue}});
    saved.push({key,created:!old});order+=10;
  }
  await audit(ctx,'ADMIN_AI_SOCIAL_BRANDS_SAVE','SocialBrand',null,'Admin AI saved '+saved.length+' social brands',{providerId,saved} as unknown as Prisma.InputJsonValue);
  return {saved,total:saved.length};
}
async function toolDiscoverCategories(ctx:AgentContext,args:Record<string,unknown>){
  const providerId=String(args.provider_id||''),brandKey=normalizeBrandKey(String(args.brand_key||'')),list=(await routes(ctx.prisma,providerId)).filter(r=>routePlatform(r)===brandKey);
  const map=new Map<string,{count:number;refill:number;noRefill:number;examples:string[];source:Set<string>}>();
  for(const route of list){
    const key=routeCandidate(route),current=map.get(key)||{count:0,refill:0,noRefill:0,examples:[],source:new Set<string>()};
    current.count++;if(route.providerRefill)current.refill++;else current.noRefill++;
    if(current.examples.length<4)current.examples.push(route.providerName||route.service.titleEn);
    if(route.providerCategory)current.source.add(route.providerCategory);map.set(key,current);
  }
  const existing=await categories(ctx.prisma);
  return {providerId,brandKey,brand:brandLabel(brandKey),totalServices:list.length,categories:[...map.entries()].map(([key,v])=>({candidateKey:key,titleEn:categoryLabel(key).en,titleFa:categoryLabel(key).fa,suggestedSlug:safeSlug(brandKey+'-'+key),serviceCount:v.count,refillCount:v.refill,noRefillCount:v.noRefill,alreadyCreated:existing.some(c=>c.platform===brandKey&&c.candidateKey===key),sourceCategories:[...v.source].slice(0,12),examples:v.examples})).sort((a,b)=>b.serviceCount-a.serviceCount)};
}
async function toolCreateCategories(ctx:AgentContext,args:Record<string,unknown>){
  requireWrite(ctx);
  const brandKey=normalizeBrandKey(String(args.brand_key||'')),raw=Array.isArray(args.categories)?args.categories:[];if(!brandKey||!raw.length)throw new Error('Brand and categories are required.');
  const old=await categories(ctx.prisma);let order=Math.max(0,...old.filter(v=>v.platform===brandKey).map(v=>v.sortOrder))+10;const saved=[];
  for(const value of raw){
    if(!value||typeof value!=='object'||Array.isArray(value))continue;
    const row=value as Record<string,unknown>,candidateKey=normalizeCandidate(String(row.candidate_key||''));if(!candidateKey)continue;
    const label=categoryLabel(candidateKey),slug=safeSlug(String(row.slug||'')||brandKey+'-'+candidateKey);if(!slug)continue;
    const data={slug,titleEn:String(row.title_en||'').trim()||label.en,titleFa:String(row.title_fa||'').trim()||label.fa,platform:brandKey,descriptionEn:'',descriptionFa:'',sortOrder:order,enabled:true,aiCandidateKey:candidateKey,createdByAdminAi:true};
    await ctx.prisma.systemSetting.upsert({where:{key:categoryKey(slug)},create:{key:categoryKey(slug),category:'social-category',description:'Social Media customer-facing category.',value:data as unknown as Prisma.InputJsonValue},update:{category:'social-category',value:data as unknown as Prisma.InputJsonValue}});
    saved.push(data);order+=10;
  }
  await audit(ctx,'ADMIN_AI_SOCIAL_CATEGORIES_SAVE','SocialCategory',null,'Admin AI saved '+saved.length+' social categories',{brandKey,saved} as unknown as Prisma.InputJsonValue);
  return {brandKey,saved,total:saved.length};
}
async function toolCategoryServices(ctx:AgentContext,args:Record<string,unknown>){
  const providerId=String(args.provider_id||''),brandKey=normalizeBrandKey(String(args.brand_key||'')),candidateKey=normalizeCandidate(String(args.candidate_key||'')),limit=Math.max(1,Math.min(100,Number(args.limit||30)));
  const list=(await routes(ctx.prisma,providerId)).filter(r=>routePlatform(r)===brandKey&&routeCandidate(r)===candidateKey);
  return {providerId,brandKey,candidateKey,count:list.length,truncated:list.length>limit,services:list.slice(0,limit).map(r=>({routeId:r.id,providerServiceId:r.providerServiceCode,name:r.providerName||r.service.titleEn,providerCategory:r.providerCategory,providerType:r.providerType,rate:r.providerRate?.toString()||null,currency:r.providerCurrency,min:r.providerMinQty,max:r.providerMaxQty,refill:r.providerRefill,cancel:r.providerCancel,alreadyAdded:obj(r.service.metadata).rawCatalog!==true}))};
}
async function toolAddServices(ctx:AgentContext,args:Record<string,unknown>){
  requireWrite(ctx);
  const providerId=String(args.provider_id||''),brandKey=normalizeBrandKey(String(args.brand_key||'')),categorySlug=safeSlug(String(args.category_slug||'')),candidateKey=normalizeCandidate(String(args.candidate_key||'')),markupNumber=Number(args.markup_percent),enabled=args.enabled!==false;
  if(!providerId||!brandKey||!categorySlug||!candidateKey)throw new Error('Provider, brand, category and candidate are required.');
  if(!Number.isFinite(markupNumber)||markupNumber<0||markupNumber>1000)throw new Error('Markup percentage must be between 0 and 1000.');
  const category=(await categories(ctx.prisma)).find(v=>v.slug===categorySlug);if(!category)throw new Error('Category does not exist.');if(category.platform!==brandKey)throw new Error('Category does not belong to this brand.');
  const list=(await routes(ctx.prisma,providerId)).filter(r=>routePlatform(r)===brandKey&&routeCandidate(r)===candidateKey);if(!list.length)throw new Error('No provider services matched.');if(list.length>500)throw new Error('Matched more than 500 services. Narrow the category first.');
  const markup=new Prisma.Decimal(markupNumber);let added=0,updated=0;
  for(const route of list){
    const sm=obj(route.service.metadata),rm=obj(route.metadata),wasRaw=sm.rawCatalog===true,name=route.providerName||route.service.titleEn;
    const detectedDrip=typeof rm._providerDripFeedDetected==='boolean'?rm._providerDripFeedDetected:Boolean(rm.dripfeed??rm.drip_feed);
    await ctx.prisma.$transaction([
      ctx.prisma.service.update({where:{id:route.serviceId},data:{titleEn:name,titleFa:fallbackPersianTitle(name),enabled,basePriceAfn:null,minQty:route.providerMinQty,maxQty:route.providerMaxQty,socialPlatform:brandKey,socialGroup:category.slug,metadata:{...sm,rawCatalog:false,addedToVelixeo:true,pricingMode:'AUTO_MARKUP',categorySlug:category.slug,publishedFromProviderId:providerId,publishedAt:String(sm.publishedAt||new Date().toISOString()),aiManaged:true,aiCandidateKey:candidateKey} as Prisma.InputJsonValue}}),
      ctx.prisma.serviceProviderRoute.update({where:{id:route.id},data:{enabled:true,markupPercent:markup,metadata:{...rm,_providerRefillDetected:typeof rm._providerRefillDetected==='boolean'?rm._providerRefillDetected:route.providerRefill,_velixeoRefillOverride:typeof rm._velixeoRefillOverride==='boolean'?rm._velixeoRefillOverride:route.providerRefill,_providerDripFeedDetected:detectedDrip,_velixeoDripFeedOverride:typeof rm._velixeoDripFeedOverride==='boolean'?rm._velixeoDripFeedOverride:detectedDrip} as Prisma.InputJsonValue}}),
    ]);
    if(wasRaw)added++;else updated++;
  }
  await audit(ctx,'ADMIN_AI_SOCIAL_SERVICES_BULK_ADD','Service',null,'Admin AI added/updated '+list.length+' services in '+category.titleEn+' with '+markupNumber+'% markup',{providerId,brandKey,categorySlug,candidateKey,markupPercent:markupNumber,enabled,added,updated} as unknown as Prisma.InputJsonValue);
  return {providerId,brandKey,categorySlug,candidateKey,markupPercent:markupNumber,matched:list.length,added,updated,enabled};
}
async function toolSetMarkup(ctx:AgentContext,args:Record<string,unknown>){
  requireWrite(ctx);
  const categorySlug=safeSlug(String(args.category_slug||'')),markup=Number(args.markup_percent);if(!categorySlug)throw new Error('Category slug is required.');if(!Number.isFinite(markup)||markup<0||markup>1000)throw new Error('Markup percentage must be between 0 and 1000.');
  const services=await ctx.prisma.service.findMany({where:{category:ServiceCategory.SOCIAL,socialGroup:categorySlug},select:{id:true}}),ids=services.map(v=>v.id);
  const result=ids.length?await ctx.prisma.serviceProviderRoute.updateMany({where:{serviceId:{in:ids}},data:{markupPercent:new Prisma.Decimal(markup)}}):{count:0};
  await audit(ctx,'ADMIN_AI_SOCIAL_CATEGORY_MARKUP','SocialCategory',categorySlug,'Admin AI set '+markup+'% markup on '+result.count+' routes',{categorySlug,markupPercent:markup,routeCount:result.count} as unknown as Prisma.InputJsonValue);
  return {categorySlug,markupPercent:markup,serviceCount:ids.length,affectedRoutes:result.count};
}
async function toolStructure(ctx:AgentContext){
  const brands=await loadSocialBrands(ctx.prisma),cats=await categories(ctx.prisma);
  return {brands:brands.map(b=>({key:b.key,titleEn:b.titleEn,titleFa:b.titleFa,enabled:b.enabled,categories:cats.filter(c=>c.platform===b.key).map(c=>({slug:c.slug,titleEn:c.titleEn,titleFa:c.titleFa,enabled:c.enabled,candidateKey:c.candidateKey}))}))};
}

const tools=[
  {type:'function',name:'list_social_providers',description:'List configured Social Media providers and synced service counts.',strict:true,parameters:{type:'object',properties:{},required:[],additionalProperties:false}},
  {type:'function',name:'sync_social_provider',description:'Synchronize a selected Social Media provider catalog. This is a write/action and should only run when the admin explicitly asks to sync/refresh.',strict:true,parameters:{type:'object',properties:{provider_id:{type:'string'}},required:['provider_id'],additionalProperties:false}},
  {type:'function',name:'discover_provider_brands',description:'Inspect a provider catalog and return detected brands such as Instagram, TikTok, Telegram with counts. Read-only.',strict:true,parameters:{type:'object',properties:{provider_id:{type:'string'}},required:['provider_id'],additionalProperties:false}},
  {type:'function',name:'create_social_brands',description:'Create/update selected customer-facing Social Media brands only after explicit admin instruction.',strict:true,parameters:{type:'object',properties:{provider_id:{type:'string'},brand_keys:{type:'array',items:{type:'string'}}},required:['provider_id','brand_keys'],additionalProperties:false}},
  {type:'function',name:'discover_brand_categories',description:'Analyze a provider brand into candidate categories such as Followers with Refill, Followers without Refill, Likes, Views, Custom Comments, etc. Read-only.',strict:true,parameters:{type:'object',properties:{provider_id:{type:'string'},brand_key:{type:'string'}},required:['provider_id','brand_key'],additionalProperties:false}},
  {type:'function',name:'create_social_categories',description:'Create selected categories under a brand only after explicit admin instruction.',strict:true,parameters:{type:'object',properties:{brand_key:{type:'string'},categories:{type:'array',items:{type:'object',properties:{candidate_key:{type:'string'},slug:{type:'string'},title_en:{type:'string'},title_fa:{type:'string'}},required:['candidate_key','slug','title_en','title_fa'],additionalProperties:false}}},required:['brand_key','categories'],additionalProperties:false}},
  {type:'function',name:'list_category_services',description:'List provider services for one detected brand/category candidate. Read-only.',strict:true,parameters:{type:'object',properties:{provider_id:{type:'string'},brand_key:{type:'string'},candidate_key:{type:'string'},limit:{type:'number'}},required:['provider_id','brand_key','candidate_key','limit'],additionalProperties:false}},
  {type:'function',name:'add_services_to_category',description:'Bulk-add matching provider services to an existing VELIXEO category with the markup percentage explicitly supplied by the admin. Never invent markup.',strict:true,parameters:{type:'object',properties:{provider_id:{type:'string'},brand_key:{type:'string'},category_slug:{type:'string'},candidate_key:{type:'string'},markup_percent:{type:'number'},enabled:{type:'boolean'}},required:['provider_id','brand_key','category_slug','candidate_key','markup_percent','enabled'],additionalProperties:false}},
  {type:'function',name:'set_category_markup',description:'Set markup for already-added Social Media routes in one category. Percentage must be explicitly supplied by the admin.',strict:true,parameters:{type:'object',properties:{category_slug:{type:'string'},markup_percent:{type:'number'}},required:['category_slug','markup_percent'],additionalProperties:false}},
  {type:'function',name:'show_existing_social_structure',description:'Show existing Social Media brands/categories in VELIXEO. Read-only.',strict:true,parameters:{type:'object',properties:{},required:[],additionalProperties:false}},
];

function instructions(lang:AdminLang){
  const language=lang==='fa'?'Always answer in Persian/Dari. Keep technical IDs unchanged.':'Always answer in English.';
  return 'You are VELIXEO Admin AI, an operations agent inside the VELIXEO admin panel. '+language+
    ' Rules: Never choose or assume markup. Profit is per instruction; if markup is missing, ask. List/inspect/show/find requests are read-only. Create/add/apply/set/execute only when explicitly requested. Use tools to do requested writes, then report exact counts. Keep Provider Services separate from VELIXEO Services. Preserve refill, cancel, drip-feed, min/max, provider IDs. Custom Comments must retain its provider type. Do not invent claims like real or guaranteed. There are intentionally no delete tools. Keep responses concise and actionable.';
}
function outputText(response:AiResponse){
  if(response.output_text&&response.output_text.trim())return response.output_text.trim();
  const parts:string[]=[];for(const item of response.output||[])for(const part of item.content||[])if(part.type==='output_text'&&part.text)parts.push(part.text);
  return parts.join('\n').trim();
}
async function aiRequest(payload:Record<string,unknown>){
  const key=String(process.env.OPENAI_API_KEY||'').trim();if(!key)throw new Error('OPENAI_API_KEY_NOT_CONFIGURED');
  const response=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify(payload)});
  const json=await response.json() as AiResponse;if(!response.ok)throw new Error(json.error?.message||'OPENAI_HTTP_'+response.status);return json;
}
async function execute(ctx:AgentContext,name:string,args:Record<string,unknown>){
  if(name==='list_social_providers')return toolProviders(ctx);
  if(name==='sync_social_provider')return toolSync(ctx,args);
  if(name==='discover_provider_brands')return toolDiscoverBrands(ctx,args);
  if(name==='create_social_brands')return toolCreateBrands(ctx,args);
  if(name==='discover_brand_categories')return toolDiscoverCategories(ctx,args);
  if(name==='create_social_categories')return toolCreateCategories(ctx,args);
  if(name==='list_category_services')return toolCategoryServices(ctx,args);
  if(name==='add_services_to_category')return toolAddServices(ctx,args);
  if(name==='set_category_markup')return toolSetMarkup(ctx,args);
  if(name==='show_existing_social_structure')return toolStructure(ctx);
  throw new Error('Unknown tool: '+name);
}
async function runAgent(prisma:PrismaClient,admin:AdminIdentity,lang:AdminLang,message:string){
  if(!configured())throw new Error('OPENAI_API_KEY_NOT_CONFIGURED');
  const state=await stateRead(prisma,admin.id);state.messages.push({role:'user',text:message,at:new Date().toISOString()});
  const ctx:AgentContext={prisma,admin,lang,allowWrites:explicitWrite(message)};
  let previous=state.previousResponseId||undefined;let input:unknown=[{role:'user',content:message}];let last=state.previousResponseId;let finalText='';
  for(let round=0;round<7;round++){
    const payload:Record<string,unknown>={model:model(),store:true,reasoning:{effort:'low'},max_output_tokens:3500,instructions:instructions(lang),tools,tool_choice:'auto',input};
    if(previous)payload.previous_response_id=previous;
    let response:AiResponse;
    try{response=await aiRequest(payload);}catch(error){if(previous&&round===0){delete payload.previous_response_id;response=await aiRequest(payload);previous=undefined;}else throw error;}
    if(response.id)last=response.id;
    const calls=(response.output||[]).filter(item=>item.type==='function_call'&&item.call_id&&item.name);
    if(!calls.length){finalText=outputText(response)||(lang==='fa'?'انجام شد.':'Done.');break;}
    const outputs=[];
    for(const call of calls){
      let args:Record<string,unknown>={};try{args=JSON.parse(call.arguments||'{}') as Record<string,unknown>;}catch{}
      try{outputs.push({type:'function_call_output',call_id:call.call_id,output:JSON.stringify({ok:true,result:await execute(ctx,String(call.name),args)})});}
      catch(error){outputs.push({type:'function_call_output',call_id:call.call_id,output:JSON.stringify({ok:false,error:error instanceof Error?error.message:'tool_failed'})});}
    }
    previous=response.id;input=outputs;
  }
  if(!finalText)finalText=lang==='fa'?'عملیات طولانی شد؛ دستور را به یک مرحله کوچک‌تر تقسیم کن.':'The operation took too many steps; split it into a smaller request.';
  state.previousResponseId=last;state.messages.push({role:'assistant',text:finalText,at:new Date().toISOString()});await stateSave(prisma,admin.id,state);return finalText;
}

async function requireAdmin(request:FastifyRequest,reply:FastifyReply,resolve:AdminResolver){
  const admin=await resolve(request);if(!admin){reply.code(401).send({error:'admin_auth_required'});return null;}return admin;
}

export async function adminAiPageBody(prisma:PrismaClient,admin:AdminIdentity,lang:AdminLang){
  const fa=lang==='fa',ready=configured(),state=await stateRead(prisma,admin.id);
  const history=state.messages.map(m=>'<div class="ai-message '+m.role+'"><div class="ai-role">'+(m.role==='user'?(fa?'شما':'You'):(fa?'دستیار VELIXEO':'VELIXEO AI'))+'</div><div class="ai-text">'+esc(m.text).replaceAll('\n','<br>')+'</div></div>').join('');
  const status=ready?(fa?'متصل و آماده':'Connected and ready'):(fa?'کلید OpenAI تنظیم نشده':'OpenAI API key is not configured');
  const empty=fa?'مثلاً بنویس: «ارائه‌دهنده‌های سوشیال را لیست کن.»':'Try: “List my Social Media providers.”';
  const note=!ready?'<div class="notice">'+(fa?'برای فعال‌شدن چت واقعی، متغیر <b>OPENAI_API_KEY</b> را در Railway تنظیم کن. مدل پیش‌فرض <b>gpt-5.6-luna</b> است.':'Set <b>OPENAI_API_KEY</b> in Railway to activate live AI. Default model: <b>gpt-5.6-luna</b>.')+'</div>':'';
  const css='<style>.ai-shell{display:grid;grid-template-columns:minmax(0,1.55fr) minmax(260px,.7fr);gap:18px}.ai-chat{min-height:610px;display:flex;flex-direction:column}.ai-head{display:flex;justify-content:space-between;gap:14px;margin-bottom:16px}.ai-status{padding:7px 10px;border-radius:999px;background:#eaf8f2;color:#167a58;font-size:11px}.ai-stream{flex:1;overflow:auto;max-height:600px;padding:8px 4px 12px;display:flex;flex-direction:column;gap:12px}.ai-message{max-width:86%;border-radius:17px;padding:12px 14px;font-size:12px;line-height:1.9;border:1px solid var(--line);background:#fff}.ai-message.user{align-self:flex-end;background:#eef9fe}.ai-message.assistant{align-self:flex-start;background:#fbfcfd}html[dir=rtl] .ai-message.user{align-self:flex-start}html[dir=rtl] .ai-message.assistant{align-self:flex-end}.ai-role{font-size:9px;color:#91a4af;margin-bottom:3px;font-weight:700}.ai-compose{border-top:1px solid var(--line);padding-top:14px;margin-top:8px}.ai-compose textarea{width:100%;min-height:88px;border:1px solid var(--line);border-radius:15px;padding:12px 14px;resize:vertical;background:#fff}.ai-compose .actions{margin-top:10px;justify-content:space-between}.ai-quick{display:grid;gap:9px}.ai-chip{width:100%;text-align:start;padding:10px 12px;border:1px solid var(--line);background:#fff;border-radius:12px;font-size:11px;color:#5f7583}.ai-rule{padding:9px 0;border-bottom:1px solid #eef2f5;font-size:10.5px;color:#647c89}@media(max-width:960px){.ai-shell{grid-template-columns:1fr}.ai-message{max-width:94%}}</style>';
  const prompt1=fa?'ارائه‌دهنده‌های سوشیال را لیست کن.':'List my Social Media providers.';
  const prompt2=fa?'ساختار فعلی برندها و دسته‌بندی‌های سوشیال را نشان بده.':'Show the current Social Media brands and categories.';
  const body='<div class="ai-shell"><div class="card ai-chat"><div class="ai-head"><div><h2>'+(fa?'دستیار هوشمند مدیریت':'Admin AI Assistant')+'</h2><p class="muted">'+(fa?'کاتالوگ را بررسی کن، برند و دسته بساز و سرویس‌ها را با درصد سودی که خودت تعیین می‌کنی اضافه کن.':'Inspect catalogs, create brands/categories and add services using the markup you specify.')+'</p></div><span class="ai-status">'+status+'</span></div>'+note+'<div id="ai-stream" class="ai-stream">'+(history||'<div class="empty">'+empty+'</div>')+'</div><div class="ai-compose"><textarea id="ai-input" '+(ready?'':'disabled')+' placeholder="'+(fa?'دستورت را بنویس…':'Type an instruction…')+'"></textarea><div class="actions"><button id="ai-reset" class="btn ghost">'+(fa?'گفتگوی جدید':'New chat')+'</button><button id="ai-send" class="btn" '+(ready?'':'disabled')+'>'+(fa?'ارسال':'Send')+'</button></div></div></div><div><div class="card"><div class="cardhead"><h3>'+(fa?'دستورهای سریع':'Quick prompts')+'</h3></div><div class="ai-quick"><button class="ai-chip" data-prompt="'+esc(prompt1)+'">'+(fa?'فهرست ارائه‌دهنده‌ها':'List providers')+'</button><button class="ai-chip" data-prompt="'+esc(prompt2)+'">'+(fa?'ساختار فعلی سوشیال':'Current social structure')+'</button></div></div><div class="card"><div class="cardhead"><h3>'+(fa?'قوانین دستیار':'Agent rules')+'</h3></div><div class="ai-rule">'+(fa?'درصد سود را خودش انتخاب نمی‌کند؛ باید تو مشخص کنی.':'It never invents markup; you specify it.')+'</div><div class="ai-rule">'+(fa?'درخواست بررسی/فهرست فقط خواندنی است.':'Inspect/list requests are read-only.')+'</div><div class="ai-rule">'+(fa?'هر تغییر در Audit Log ثبت می‌شود.':'Every write is recorded in Audit Log.')+'</div><div class="ai-rule">'+(fa?'ابزار حذف در این نسخه وجود ندارد.':'This version intentionally has no delete tools.')+'</div></div></div></div>';
  const script="<script>(()=>{const i=document.getElementById('ai-input'),s=document.getElementById('ai-send'),r=document.getElementById('ai-reset'),o=document.getElementById('ai-stream'),fa="+(fa?'true':'false')+";const x=v=>String(v??'').replace(/[&<>\\\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\\\"':'&quot;',\\\"'\\\":'&#39;'}[c]));function a(role,text){const e=o.querySelector('.empty');if(e)e.remove();const n=document.createElement('div');n.className='ai-message '+role;n.innerHTML='<div class=\\\"ai-role\\\">'+(role==='user'?(fa?'شما':'You'):(fa?'دستیار VELIXEO':'VELIXEO AI'))+'</div><div class=\\\"ai-text\\\">'+x(text).replace(/\\\\n/g,'<br>')+'</div>';o.appendChild(n);o.scrollTop=o.scrollHeight;}async function send(){const m=String(i.value||'').trim();if(!m||s.disabled)return;a('user',m);i.value='';s.disabled=true;try{const res=await fetch('/admin/v3/agent/chat',{method:'POST',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify({message:m})}),p=await res.json();if(!res.ok)throw new Error(p.error||'agent_failed');a('assistant',p.text||'');}catch(e){a('assistant',(fa?'خطا: ':'Error: ')+String(e&&e.message||e));}finally{s.disabled=false;i.focus();}}s?.addEventListener('click',send);i?.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();send();}});r?.addEventListener('click',async()=>{r.disabled=true;try{await fetch('/admin/v3/agent/reset',{method:'POST'});o.innerHTML='<div class=\\\"empty\\\">'+(fa?'گفتگوی جدید آماده است.':'New chat is ready.')+'</div>';}finally{r.disabled=false;}});document.querySelectorAll('[data-prompt]').forEach(b=>b.addEventListener('click',()=>{if(!i.disabled){i.value=b.dataset.prompt||'';i.focus();}}));o.scrollTop=o.scrollHeight;})()</script>";
  return css+body+script;
}

export function registerAdminAiAgent(app:FastifyInstance,prisma:PrismaClient,resolve:AdminResolver){
  app.get('/admin/v3/agent',async(request,reply)=>{
    const admin=await resolve(request);if(!admin)return reply.code(303).redirect('/admin/login');
    const lang=adminLangFromRequest(request);
    const body=await adminAiPageBody(prisma,admin,lang);
    return reply.type('text/html; charset=utf-8').send(renderAdminV3Page(admin,'social',body,'','',false,lang,lang==='fa'?'دستیار هوشمند':'Admin AI Assistant',lang==='fa'?'مدیریت هوشمند کاتالوگ و ارائه‌دهندگان':'AI-powered provider and catalog management'));
  });
  app.post('/admin/v3/agent/chat',async(request,reply)=>{
    const admin=await requireAdmin(request,reply,resolve);if(!admin)return;
    const body=(request.body||{}) as Record<string,unknown>,message=String(body.message||'').trim().slice(0,5000);if(!message)return reply.code(400).send({error:'message_required'});
    const lang=adminLangFromRequest(request);
    try{return reply.header('Cache-Control','no-store').send({ok:true,text:await runAgent(prisma,admin,lang,message),model:model()});}
    catch(error){const raw=error instanceof Error?error.message:'agent_failed';request.log.error({err:error},'admin_ai_agent_failed');return reply.code(raw==='OPENAI_API_KEY_NOT_CONFIGURED'?503:400).send({ok:false,error:raw==='OPENAI_API_KEY_NOT_CONFIGURED'?(lang==='fa'?'OPENAI_API_KEY هنوز در Railway تنظیم نشده است.':'OPENAI_API_KEY is not configured in Railway yet.'):raw});}
  });
  app.post('/admin/v3/agent/reset',async(request,reply)=>{const admin=await requireAdmin(request,reply,resolve);if(!admin)return;await prisma.systemSetting.deleteMany({where:{key:stateKey(admin.id)}});return reply.header('Cache-Control','no-store').send({ok:true});});
}
