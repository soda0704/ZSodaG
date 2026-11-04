// Build mutually aligned PBR maps from the generated height master. Node built-ins only.
const fs=require('fs'),zlib=require('zlib'),path=require('path');
const DIR=path.resolve('assets/environments/snow/arctic_powder_native');
// Power-of-two working grid is used only for the spectral seam solve, never stored as a larger texture.
let N=2048,COUNT=N*N;
function decode(file){const b=fs.readFileSync(file);let w=b.readUInt32BE(16),h=b.readUInt32BE(20),channels=b[25]===2?3:4;if(b[24]!==8)throw Error('8-bit source required');let chunks=[];for(let at=8;at<b.length;){let len=b.readUInt32BE(at);if(b.toString('ascii',at+4,at+8)==='IDAT')chunks.push(b.subarray(at+8,at+8+len));at+=12+len;}let raw=zlib.inflateSync(Buffer.concat(chunks)),stride=w*channels,out=Buffer.alloc(w*h*channels);const paeth=(a,b,c)=>{let p=a+b-c,aa=Math.abs(p-a),bb=Math.abs(p-b),cc=Math.abs(p-c);return aa<=bb&&aa<=cc?a:bb<=cc?b:c;};for(let y=0;y<h;y++){let f=raw[y*(stride+1)];for(let x=0;x<stride;x++){let a=x>=channels?out[y*stride+x-channels]:0,up=y?out[(y-1)*stride+x]:0,c=y&&x>=channels?out[(y-1)*stride+x-channels]:0;out[y*stride+x]=(raw[y*(stride+1)+1+x]+(f===0?0:f===1?a:f===2?up:f===3?Math.floor((a+up)/2):paeth(a,up,c)))&255;}}return {w,h,channels,out};}
const crcTable=Uint32Array.from({length:256},(_,n)=>{let c=n;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
function chunk(type,data){let t=Buffer.from(type),v=Buffer.concat([t,data]),crc=0xffffffff;for(const x of v)crc=crcTable[(crc^x)&255]^(crc>>>8);let b=Buffer.alloc(data.length+12);b.writeUInt32BE(data.length);t.copy(b,4);data.copy(b,8);b.writeUInt32BE((crc^0xffffffff)>>>0,b.length-4);return b;}
function png(name,data,channels=3,depth=8){let header=Buffer.alloc(13);header.writeUInt32BE(N,0);header.writeUInt32BE(N,4);header[8]=depth;header[9]=channels===1?0:channels===3?2:6;const stride=N*channels*(depth/8),scan=Buffer.alloc((stride+1)*N);for(let y=0;y<N;y++)data.copy(scan,y*(stride+1)+1,y*stride,(y+1)*stride);fs.writeFileSync(path.join(DIR,name),Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(scan,{level:6})),chunk('IEND',Buffer.alloc(0))]));}
function fft(re,im,inverse){let n=re.length;for(let i=1,j=0;i<n;i++){let bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){[re[i],re[j]]=[re[j],re[i]];[im[i],im[j]]=[im[j],im[i]];}}for(let len=2;len<=n;len<<=1){let angle=(inverse?2:-2)*Math.PI/len,wr0=Math.cos(angle),wi0=Math.sin(angle);for(let i=0;i<n;i+=len){let wr=1,wi=0;for(let j=0;j<len/2;j++){let a=i+j,b=a+len/2,vr=re[b]*wr-im[b]*wi,vi=re[b]*wi+im[b]*wr;re[b]=re[a]-vr;im[b]=im[a]-vi;re[a]+=vr;im[a]+=vi;let t=wr;wr=t*wr0-wi*wi0;wi=t*wi0+wi*wr0;}}}if(inverse)for(let i=0;i<n;i++){re[i]/=n;im[i]/=n;}}
function fft2(re,im,inverse){let r=new Float64Array(N),q=new Float64Array(N);for(let y=0;y<N;y++){r.set(re.subarray(y*N,(y+1)*N));q.set(im.subarray(y*N,(y+1)*N));fft(r,q,inverse);re.set(r,y*N);im.set(q,y*N);}for(let x=0;x<N;x++){for(let y=0;y<N;y++){r[y]=re[y*N+x];q[y]=im[y*N+x];}fft(r,q,inverse);for(let y=0;y<N;y++){re[y*N+x]=r[y];im[y*N+x]=q[y];}}}
const source=decode(path.join(DIR,'generated_height_source.png'));let height=new Float64Array(COUNT);
// Bicubic reconstruction is not invented native detail: the source remains archived at 1254px.
function cubic(a,b,c,d,t){return b+.5*t*(c-a+t*(2*a-5*b+4*c-d+t*(3*(b-c)+d-a)));}
const pixel=(x,y)=>source.out[(Math.max(0,Math.min(source.h-1,y))*source.w+Math.max(0,Math.min(source.w-1,x)))*source.channels]/255;
for(let y=0;y<N;y++)for(let x=0;x<N;x++){let sx=x*(source.w-1)/(N-1),sy=y*(source.h-1)/(N-1),ix=Math.floor(sx),iy=Math.floor(sy),rows=[];for(let dy=-1;dy<=2;dy++)rows.push(cubic(pixel(ix-1,iy+dy),pixel(ix,iy+dy),pixel(ix+1,iy+dy),pixel(ix+2,iy+dy),sx-ix));height[y*N+x]=cubic(...rows,sy-iy);}
// Periodic-plus-smooth decomposition: solve the boundary Poisson equation in Fourier space.
// Removes the source edge discontinuity without mirrored quadrants or cross-fading texture cells.
const smooth=new Float64Array(COUNT),imag=new Float64Array(COUNT);
for(let x=0;x<N;x++){let v=height[(N-1)*N+x]-height[x];smooth[x]+=v;smooth[(N-1)*N+x]-=v;}
for(let y=0;y<N;y++){let a=y*N,b=a+N-1,v=height[b]-height[a];smooth[a]+=v;smooth[b]-=v;}
fft2(smooth,imag,false);
for(let y=0;y<N;y++)for(let x=0;x<N;x++){let i=y*N+x,den=2*Math.cos(2*Math.PI*x/N)+2*Math.cos(2*Math.PI*y/N)-4;if(i===0){smooth[i]=0;imag[i]=0;}else{smooth[i]/=den;imag[i]/=den;}}
fft2(smooth,imag,true);for(let i=0;i<COUNT;i++)height[i]-=smooth[i];
// Suppress artificial broad height clouds, keeping granular and shallow meso relief.
imag.fill(0);fft2(height,imag,false);let blurRe=height.slice();const blurIm=imag.slice();
for(let y=0;y<N;y++)for(let x=0;x<N;x++){let i=y*N+x,kx=Math.min(x,N-x),ky=Math.min(y,N-y),k2=(kx*kx+ky*ky)*Math.pow(2*Math.PI/N,2);let suppress=1-.80*Math.exp(-.5*32*32*k2),fine=Math.exp(-.5*.65*.65*k2);height[i]*=suppress*fine;imag[i]*=suppress*fine;let aoBlur=Math.exp(-.5*6*6*k2);blurRe[i]*=suppress*fine*aoBlur;blurIm[i]*=suppress*fine*aoBlur;}
fft2(height,imag,true);fft2(blurRe,blurIm,true);
let mean=0;for(const h of height)mean+=h;mean/=COUNT;let variance=0;for(const h of height)variance+=(h-mean)**2;let amplitude=.0008/Math.sqrt(variance/COUNT);
for(let i=0;i<COUNT;i++){height[i]=Math.max(-.0035,Math.min(.0035,(height[i]-mean)*amplitude));blurRe[i]=(blurRe[i]-mean)*amplitude;}
// Return to the generator's native resolution BEFORE deriving normals and the PBR maps.
const oldSize=N;const nativeSize=source.w;
function nativeResample(input){const out=new Float64Array(nativeSize*nativeSize);for(let y=0;y<nativeSize;y++)for(let x=0;x<nativeSize;x++){const px=x*oldSize/nativeSize,py=y*oldSize/nativeSize,ix=Math.floor(px),iy=Math.floor(py),rows=[];for(let j=-1;j<=2;j++){const row=((iy+j+oldSize)%oldSize)*oldSize;rows.push(cubic(input[row+(ix-1+oldSize)%oldSize],input[row+ix%oldSize],input[row+(ix+1)%oldSize],input[row+(ix+2)%oldSize],px-ix));}out[y*nativeSize+x]=cubic(...rows,py-iy);}return out;}
height=nativeResample(height);blurRe=nativeResample(blurRe);N=nativeSize;COUNT=N*N;
const albedo=Buffer.alloc(COUNT*3),normal=Buffer.alloc(COUNT*3),rough=Buffer.alloc(COUNT),ao=Buffer.alloc(COUNT),orm=Buffer.alloc(COUNT*3),height16=Buffer.alloc(COUNT*2);
const clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v)),byte=v=>Math.round(clamp(v)*255),srgb=v=>v<=.0031308?v*12.92:1.055*Math.pow(v,1/2.4)-.055;
const spacing=2/N;
for(let y=0;y<N;y++)for(let x=0;x<N;x++){let i=y*N+x,h=height[i],dx=(height[y*N+(x+1)%N]-height[y*N+(x+N-1)%N])/(2*spacing),dy=(height[((y+1)%N)*N+x]-height[((y+N-1)%N)*N+x])/(2*spacing),len=Math.hypot(dx,dy,1),grain=clamp(h/.0025,-1,1),cavity=clamp((blurRe[i]-h)/.0025);normal[i*3]=byte(-dx/len*.5+.5);normal[i*3+1]=byte(dy/len*.5+.5);normal[i*3+2]=byte(1/len*.5+.5);for(let c=0;c<3;c++)albedo[i*3+c]=byte(srgb([.80,.805,.81][c]+grain*.008));rough[i]=byte(.91+cavity*.055-grain*.012);ao[i]=byte(1-cavity*.10);orm[i*3]=ao[i];orm[i*3+1]=rough[i];orm[i*3+2]=0;height16.writeUInt16BE(Math.round(clamp(h/.007+.5)*65535),i*2);}
png('arctic_snow_albedo.png',albedo);png('arctic_snow_normal_gl.png',normal);png('arctic_snow_roughness.png',rough,1);png('arctic_snow_ao.png',ao,1);png('arctic_snow_orm.png',orm);png('arctic_snow_height.png',height16,1,16);
// Validate periodic derivative contacts compared to regular adjacent height samples.
let edge=0,edgeCount=0,inside=0,insideCount=0;
for(let y=0;y<N;y++){edge+=Math.abs(height[y*N]-height[y*N+N-1]);edgeCount++;for(let x=0;x<N-1;x++){inside+=Math.abs(height[y*N+x+1]-height[y*N+x]);insideCount++;}}
for(let x=0;x<N;x++){edge+=Math.abs(height[x]-height[(N-1)*N+x]);edgeCount++;}
const validation={size:[N,N],generated_source:[source.w,source.h],physical_tile_metres:2,height_range_metres:[-.0035,.0035],wrap_height_difference_mean:edge/edgeCount,adjacent_height_difference_mean:inside/insideCount,edge_to_interior_ratio:(edge/edgeCount)/(inside/insideCount),normal_convention:'OpenGL, +Y',color_space:'Albedo sRGB; Normal/ORM/Height linear',provenance:'AI-generated grayscale master; aligned PBR maps derived numerically, not measured photogrammetry'};
fs.writeFileSync(path.join(DIR,'validation.json'),JSON.stringify(validation,null,2));console.log(validation);
if(validation.edge_to_interior_ratio>1.5)throw Error('Seam discontinuity exceeds ordinary interior relief');
