from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import shutil
R=Path(__file__).resolve().parent
T=R.parents[2]/'assets/models/doors/medical_hermetic_door/textures/realistic_2k';T.mkdir(parents=True,exist_ok=True)
old=R.parents[2]/'assets/models/doors/living_hermetic_door/textures/realistic_2k'
for n in ['paint_microheight_source.png','reference_frame_color.png','reference_doors_color.png']:shutil.copyfile(old/n,T/n)
im=Image.new('RGB',(1600,180));d=ImageDraw.Draw(im);font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',145)
d.text((800,90),'MEDICAL SECTION',font=font,fill='white',anchor='mm');im.save(R/'sign_mask.png')
s=(R.parent/'LivingHermeticDoor/texture_realistic.py').read_text()
s=s.replace("living_hermetic_door_prepared.blend","medical_prepared.blend").replace('living_hermetic_door','medical_hermetic_door').replace('LivingHermeticDoor','MedicalHermeticDoor')
s=s.replace("micro=read_image", "sign=read_image(ROOT/'sign_mask.png').mean(2)\nmicro=read_image")
s=s.replace('(.30,.315,.31)','(.57,.61,.60)').replace('( .065,.077,.079)','( .15,.20,.21)').replace('(.082,.151,.10)','(.035,.28,.25)')
s=s.replace('chips,abrasion*.65','chips*.30,abrasion*.25').replace('grime[:,None]*.48','grime[:,None]*.20')
s=s.replace("col,phys,h=evaluate(points,np.array(p.normal),category,*edgegroups[p.index])", """col,phys,h=evaluate(points,np.array(p.normal),category,*edgegroups[p.index])
            if o.name=='MedicalSign' and abs(p.normal.y)>.7:
                u=points[:,0]/3.25+.5
                if p.normal.y>0:u=1-u
                v=(points[:,2]-5.7)/.32+.5
                mask=sample(sign,np.clip(u,0,.99999),np.clip(v,0,.99999))*((u>0)&(u<1)&(v>0)&(v<1))
                col[:]=np.array([.025,.12,.115]);col=col*(1-mask[:,None])+np.array([.85,.91,.87])*mask[:,None]
                phys[:,1]=.43;phys[:,2]=.01
""")
s=s.replace("target=(0,0,1.5)","target=(0,0,3)")
s=s.replace("((-3,-2,4.5),1150,2.5),((4,-1,2.8),650,3),((0,3,4),1100,3)","((-6,-4,9),4600,5),((8,-2,5.6),2600,6),((0,6,8),4400,6)")
s=s.replace('(3.2,-7,3.3)','(5,-14,6.3)').replace('ortho_scale=4.1','ortho_scale=8.0').replace('(-2.8,7,3.2)','(-5,14,6.3)')
s=s.replace('(-1.8,-4,2.6)','(0,-8,6.4)').replace('ortho_scale=1.22','ortho_scale=4.1').replace('(-.86,0,1.88)','(0,0,5.3)')
(R/'texture_medical.py').write_text(s)
