"""Deterministic label maps and BGR frames. Never opens hardware."""
import cv2
import numpy as np

COLORS={1:(0,220,0),2:(220,0,0),3:(0,140,240)}
def blank():return np.zeros((240,320),np.uint8)
def rectangle(color=1):
    a=blank();a[70:130,30:120]=color;return a
def separated():
    a=rectangle();a[70:130,160:250]=2;return a
def joined(a=1,b=2):
    m=rectangle(a);m[70:130,120:210]=b;return m
def three():
    a=blank();a[70:130,30:100]=1;a[70:130,100:170]=2;a[70:130,170:240]=3;return a
def bgr(labels):
    image=np.zeros((*labels.shape,3),np.uint8)
    for id,color in COLORS.items():image[labels==id]=color
    return image

def scenarios():
    several=blank();several[100:130,20:280]=2
    for x in (20,120,240):several[40:100,x:x+40]=1
    hole=blank();hole[20:190,20:210]=1;hole[50:150,60:180]=0
    hole[80:120,210:260]=2;hole[120:140,210:260]=3
    concave=blank();concave[30:170,30:70]=1;concave[130:170,70:220]=3
    corner=blank();corner[40:80,20:80]=1;corner[80:120,80:140]=3
    thin=blank();thin[60:100,20:60]=1;thin[100:101,20:240]=3
    specs=[('01_green',[(rectangle(1),10)]),('02_blue',[(rectangle(2),10)]),
           ('03_orange',[(rectangle(3),10)]),('04_separate',[(separated(),10)]),
           ('05_green_orange',[(joined(1,3),10)]),('06_blue_orange',[(joined(2,3),10)]),
           ('07_three_materials',[(three(),10)]),('08_two_green_joined',[(joined(1,1),10)]),
           ('09_three_green_regions',[(several,10)]),
           ('10_merge',[(separated(),10),(joined(),10)]),
           ('11_split',[(separated(),10),(joined(),10),(separated(),12)]),
           ('12_holes',[(hole,10)]),('13_concave',[(concave,10)]),
           ('14_corner',[(corner,12)]),('15_thin',[(thin,12)]),
           ('16_chromatic_noise',[(three(),10)]),('17_near_hues',[(three(),10)]),
           ('18_lighting',[(three(),10)]),
           ('19_brief_loss',[(three(),10),(blank(),2),(three(),10)]),
           ('20_reappearance',[(three(),10),(blank(),12),(three(),10)])]
    for name,stages in specs:
        frames=[];refs=[]
        for labels,n in stages:
            for _ in range(n):
                image=bgr(labels)
                if name=='16_chromatic_noise':
                    allowed=cv2.dilate((labels>0).astype('uint8'),np.ones((7,7),np.uint8))==0
                    for y,x in [(y,x) for y in range(4,235,14) for x in range(4,315,14) if allowed[y,x]][:60]:
                        image[y,x]=COLORS[1+(x+y)%3]
                if name=='17_near_hues':
                    hsv=cv2.cvtColor(image,cv2.COLOR_BGR2HSV)
                    hsv[labels==1,0]=35;hsv[labels==2,0]=95;hsv[labels==3,0]=25
                    hsv[5:20,5:40]=(29,240,200) # in the unclassified gap
                    image=cv2.cvtColor(hsv,cv2.COLOR_HSV2BGR)
                if name=='18_lighting':
                    hsv=cv2.cvtColor(image,cv2.COLOR_BGR2HSV)
                    hsv[:,:,1]=(hsv[:,:,1].astype(float)*.68).astype('uint8')
                    hsv[:,:,2]=(hsv[:,:,2].astype(float)*.65).astype('uint8')
                    image=cv2.cvtColor(hsv,cv2.COLOR_HSV2BGR)
                frames.append(image);refs.append(labels.copy())
        yield name,frames,refs
