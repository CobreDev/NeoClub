"""Generates the Liquid Glass Gold app icon (an Icon Composer .icon document) from the white club wordmark.
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
def honeycomb_layer(path,line):
    """Transparent honeycomb lines only, no fill: for Tinted/Clear the icon's background is the system's own material
    (an opaque image there blocks it, so the tile looked flat and gray next to every other app's glass tile)."""
    over=Image.new('RGBA',(S,S),(0,0,0,0)); d=ImageDraw.Draw(over); r=96; w=r*math.sqrt(3)
    for row in range(-1,12):
        for col in range(-1,12): d.polygon(hexagon(col*w+(w/2 if row%2 else 0),row*r*1.5,r-5),outline=line,width=5)
    over.save(path)
def logo_layer(mask,color,width,path):
    h=int(mask.height*width/mask.width); m=mask.resize((width,h),Image.LANCZOS)
    s=Image.new('RGBA',(width,h),color+(255,)); s.putalpha(m)
    c=Image.new('RGBA',(S,S),(0,0,0,0)); c.alpha_composite(s,((S-width)//2,(S-h)//2)); c.save(path)
def _unused_hex_layer(path,r,color):
    m=Image.new('L',(S*2,S*2),0); ImageDraw.Draw(m).polygon(hexagon(S,S,r*2,rot=0),fill=255)
    m=m.filter(ImageFilter.GaussianBlur(40)).point(lambda v:255 if v>128 else 0).filter(ImageFilter.GaussianBlur(1.5)).resize((S,S),Image.LANCZOS)
    s=Image.new('RGBA',(S,S),color+(255,)); s.putalpha(m); s.save(path)
def grp(layers,name,sh,translucency=None):
    g={"layers":layers,"name":name,"shadow":{"kind":"neutral","opacity":sh},"specular":True}
    if translucency is not None: g["translucency"]={"enabled":True,"value":translucency}
    return g
def spec(name,default,dark=None,tinted=None,clear=None):
    v=[{"value":default}]
    if dark: v.append({"appearance":"dark","value":dark})
    if tinted: v.append({"appearance":"tinted","value":tinted})
    if clear: v.append({"appearance":"clear","value":clear})
    return v

def make_gold(out,name='AppIconGold',tinted_bg=True):
    """Gold with the original's colours; Dark and Tinted get their own layers, because dark-on-gold becomes dark-on-dark
    (illegible) when the system darkens or tints it: a dark background with a gold wordmark (Dark), and a dark
    background with a white wordmark (Tinted, which the system then colours)."""
    d=os.path.join(out,name+'.icon'); os.makedirs(d+'/Assets',exist_ok=True)
    GOLD=((0xFF,0xD0,0x55),(0xF2,0xB2,0x3E),(0xE0,0x96,0x28))
    background(d+'/Assets/bg.png',*GOLD,(255,255,255,58))
    honeycomb_layer(d+'/Assets/bg-tinted.png',(255,255,255,40))
    logo_layer(MAIN,(0x00,0x5F,0x8C),LW,d+'/Assets/logo.png');   logo_layer(ACCENT,(0x12,0x16,0x1E),LW,d+'/Assets/club.png')
    logo_layer(MAIN,(0xF9,0xD5,0x48),LW,d+'/Assets/logo-dark.png'); logo_layer(ACCENT,(0xFF,0xF3,0xC9),LW,d+'/Assets/club-dark.png')
    logo_layer(MAIN,(255,255,255),LW,d+'/Assets/logo-tinted.png');   logo_layer(ACCENT,(255,255,255),LW,d+'/Assets/club-tinted.png')
    # Icon Composer doesn't honour per-appearance image swaps written by hand, but it does honour `hidden-specializations`,
    # so each look has its own layers and the others are hidden in that appearance.
    LOOKS={'':('light',None),'-dark':('dark',None),'-tinted':('tinted',None)}
    def L(img,name,look,glass=True):
        hide={'':[{"value":False},{"appearance":"dark","value":True},{"appearance":"tinted","value":True}],
              '-dark':[{"value":True},{"appearance":"dark","value":False}],
              '-tinted':[{"value":True},{"appearance":"tinted","value":False}]}[look]
        return {"glass":glass,"image-name":img,"name":name+look,"hidden-specializations":hide,"position":{"scale":1,"translation-in-points":[0,0]}}
    groups=[grp([L('club'+k+'.png','Club',k) for k in ('','-dark','-tinted')],'Club',0.5),
            grp([L('logo'+k+'.png','Wordmark',k) for k in ('','-dark','-tinted')],'Wordmark',0.5),
            grp([L('bg'+k+'.png','background',k,False) for k in ('','-tinted')],'Background',0)]  # bg-tinted: honeycomb lines on the system's material
    # Dark: no background layer of ours at all; the icon's fill becomes the system's own dark material, so it matches
    # every other app's dark icon (a hand-picked gray never quite did).
    # No colour in the icon's own fill: gold lives only on the Light look's background layer. A gold fill (even one
    # overridden for Dark) made iOS tint the whole Dark icon yellow on the phone, though Icon Composer's renderer didn't.
    for g in groups:
        for l in g['layers']:
            if l['name']=='background': l['hidden-specializations']=[{"value":False},{"appearance":"dark","value":True},{"appearance":"tinted","value":True}]
    json.dump({"fill":"automatic","groups":groups,
      "supported-platforms":{"squares":"shared"}},open(d+'/icon.json','w'),indent=2)

def generate():
    out=sys.argv[1]; os.makedirs(out,exist_ok=True)
    make_gold(out)   # the original's colours, with Dark and Tinted/Clear looks


if __name__=='__main__': generate()
