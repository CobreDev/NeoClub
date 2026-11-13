"""Generates the Liquid Glass app icon variants (Icon Composer .icon documents) from the white club wordmark.
Usage: python3 icons/build_icons.py NeoClub/Resources/AppIcons   (needs Pillow). Render previews with Icon Composer's ictool."""
import json,os,math,sys,collections
from PIL import Image, ImageDraw, ImageFilter
S=1024
WORDMARK=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','NeoClub/Resources/Brand/club_logo_2026.png')
LOGO=Image.open(WORDMARK).convert('RGBA')
LW=967   # the original icon's wordmark spans 967 of its 1024 px (arc tip to arc tip)

def components_mask():
    """Alpha masks: the arc halves + 'Club' (accent) and everything else (main)."""
    a=LOGO.split()[3]; W,H=a.size; px=a.load(); seen=[[0]*W for _ in range(H)]
    accent=Image.new('L',(W,H),0); apx=accent.load()
    for y0 in range(H):
        for x0 in range(W):
            if px[x0,y0]>0 and not seen[y0][x0]:
                q=collections.deque([(x0,y0)]); seen[y0][x0]=1; pts=[]
                while q:
                    x,y=q.popleft(); pts.append((x,y))
                    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
                        nx,ny=x+dx,y+dy
                        if 0<=nx<W and 0<=ny<H and not seen[ny][nx] and px[nx,ny]>0: seen[ny][nx]=1; q.append((nx,ny))
                ys=[p[1] for p in pts]
                if min(ys)>=250 and max(ys)>=300 and len(pts)>2000:
                    for x,y in pts: apx[x,y]=px[x,y]
    main=Image.new('L',(W,H)); mpx=main.load()
    for y in range(H):
        for x in range(W): mpx[x,y]=0 if apx[x,y] else px[x,y]
    return main,accent
MAIN,ACCENT=components_mask()

def hexagon(cx,cy,r,rot=30): return [(cx+r*math.cos(math.radians(rot+60*i)),cy+r*math.sin(math.radians(rot+60*i))) for i in range(6)]
def background(path,c1,c2,c3,line):
    im=Image.new('RGB',(S,S)); px=im.load()
    for y in range(S):
        for x in range(S):
            t=(x*0.35+y*0.65)/S
            a,b,u=(c1,c2,t/0.5) if t<0.5 else (c2,c3,(t-0.5)/0.5)
            px[x,y]=tuple(int(a[i]+(b[i]-a[i])*u) for i in range(3))
    over=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(over); r=96; w=r*math.sqrt(3)
    for row in range(-1,12):
        for col in range(-1,12): d.polygon(hexagon(col*w+(w/2 if row%2 else 0),row*r*1.5,r-5),outline=line,width=5)
    im=im.convert('RGBA'); im.alpha_composite(over); im.convert('RGB').save(path)
def logo_layer(mask,color,width,path):
    h=int(mask.height*width/mask.width); m=mask.resize((width,h),Image.LANCZOS)
    s=Image.new('RGBA',(width,h),color+(255,)); s.putalpha(m)
    c=Image.new('RGBA',(S,S),(0,0,0,0)); c.alpha_composite(s,((S-width)//2,(S-h)//2)); c.save(path)
def _unused_hex_layer(path,r,color):
    m=Image.new('L',(S*2,S*2),0); ImageDraw.Draw(m).polygon(hexagon(S,S,r*2,rot=0),fill=255)
    m=m.filter(ImageFilter.GaussianBlur(40)).point(lambda v:255 if v>128 else 0).filter(ImageFilter.GaussianBlur(1.5)).resize((S,S),Image.LANCZOS)
    s=Image.new('RGBA',(S,S),color+(255,)); s.putalpha(m); s.save(path)
def lay(img,name,glass=True): return {"glass":glass,"image-name":img,"name":name,"position":{"scale":1,"translation-in-points":[0,0]}}
def grp(layers,name,sh,translucency=None):
    g={"layers":layers,"name":name,"shadow":{"kind":"neutral","opacity":sh},"specular":True}
    if translucency is not None: g["translucency"]={"enabled":True,"value":translucency}
    return g
def write(out,name,groups,fill):
    d=os.path.join(out,name+'.icon'); json.dump({"fill":{"automatic-gradient":fill},"groups":groups,"supported-platforms":{"squares":"shared"}},open(d+'/icon.json','w'),indent=2)
def make(out,name,bg,main_col,accent_col,line,fill):
    d=os.path.join(out,name+'.icon'); os.makedirs(d+'/Assets',exist_ok=True)
    background(d+'/Assets/bg.png',*bg,line); logo_layer(MAIN,main_col,LW,d+'/Assets/logo.png'); logo_layer(ACCENT,accent_col,LW,d+'/Assets/club.png')
    write(out,name,[grp([lay('club.png','Club')],'Club',0.5),grp([lay('logo.png','Wordmark')],'Wordmark',0.5),grp([lay('bg.png','background',False)],'Background',0)],fill)

out=sys.argv[1]; os.makedirs(out,exist_ok=True)
GOLD=((0xFF,0xD0,0x55),(0xF2,0xB2,0x3E),(0xE0,0x96,0x28)); BLUE=((0x2F,0x9B,0xE0),(0x00,0x5E,0x9A),(0x14,0x2A,0x66))
YF="extended-srgb:0.94000,0.70000,0.27000,1.00000"; BF="extended-srgb:0.00000,0.36900,0.60400,1.00000"
make(out,'AppIconGold',GOLD,(0x00,0x5F,0x8C),(0x12,0x16,0x1E),(255,255,255,58),YF)            # the original's colours
make(out,'AppIconGoldWhite',GOLD,(255,255,255),(0x1C,0x38,0x72),(255,255,255,70),YF)       # white wordmark, navy Club
make(out,'AppIconBlueGold',BLUE,(255,255,255),(0xF9,0xD5,0x48),(255,255,255,34),BF)           # white wordmark, yellow Club
# blue, white wordmark only (no accent layer)
d=os.path.join(out,'AppIconBlue.icon'); os.makedirs(d+'/Assets',exist_ok=True)
background(d+'/Assets/bg.png',*BLUE,(255,255,255,34)); full=Image.merge('L',(Image.eval(MAIN,lambda v:v),)) if False else None
whole=Image.new('L',LOGO.size); whole.paste(LOGO.split()[3]); logo_layer(whole,(255,255,255),LW,d+'/Assets/logo.png')
write(out,'AppIconBlue',[grp([lay('logo.png','Wordmark')],'Wordmark',0.6),grp([lay('bg.png','background',False)],'Background',0)],BF)
