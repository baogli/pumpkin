"""Build native typography, shapes and animation for the Pumpkin launch composition.
Run from repository root after `tsrct project checkout` to the working JSON.
Assets and OFL fonts are packaged in Pumpkin.tsrct; no network calls are made.
"""
from pathlib import Path
import json

WORK = Path(__file__).parent / '.tesseract-work'
doc = json.loads((WORK / 'editable.json').read_text())
doc['dimensions'] = {'width': 1600, 'height': 900}
doc['duration'] = 21
doc['backgroundColor'] = [0.98, 0.93, 0.84, 1]
doc['composition']['name'] = 'Pumpkin — Every file gets its midnight'
doc['composition']['layers'] = []
actions = []
seq = 10
cream = [0.98, 0.93, 0.84, 1]
green = [0.07, 0.18, 0.13, 1]
orange = [0.97, 0.38, 0.10, 1]
muted = [0.34, 0.40, 0.33, 1]

def new_id():
 global seq
 seq += 1
 return seq

def tr(x, y, anchor=(0, 0), scale=100, rotation=0):
 return {'anchorPoint': list(anchor), 'position': [x, y], 'scale': [scale, scale], 'rotation': rotation, 'opacity': 100}

def rng(start, end):
 return {'start': round(start*1000), 'duration': round((end-start)*1000)}

def keys(layer, prop, poses, smooth=True):
 actions.append({'type':'setFxPropertyKeyframes','compositionId':'main','property':{'layerId':layer,'propertyType':prop},'keyframes':[
  {'id':f'{layer}-{prop}-{i}', 'layerTime':round(t*1000), 'value':{'type':'float','value':v}, 'easing':{'type':'cubicBezier','x1':0.18,'y1':0.8,'x2':0.22,'y2':1} if smooth and i else {'type':'linear'}}
  for i,(t,v) in enumerate(poses)]})

def entrance(layer, duration, y=None, delay=0):
 keys(layer,'opacity',[(0,0),(delay+0.32,100),(duration-0.14,100),(duration-0.02,0)])
 if y is not None: keys(layer,'positionY',[(0,y+25),(delay+0.42,y),(duration,y)])

def text(name, content, x, y, w, h, size, start, end, color=green, headline=False, animate=True):
 i = new_id()
 actions.append({'type':'createFxTextLayer','compositionId':'main','layerId':i,'insertIndex':0,'name':name,'activeRange':rng(start,end),'transform':tr(x,y),
  'sourceText':{'text':content,'fontFamily':'Fredoka Light' if headline else 'DM Sans 9pt','fontStyle':'Medium' if headline else 'Regular','fontSize':size,'fillColor':color,'strokeWidth':0,'justification':'left','boxText':True,'boxPosition':[0,0],'boxSize':[w,h],'leading':size*1.12}})
 if animate: entrance(i,end-start,y)
 return i

def rect(name, x, y, w, h, color, start, end, roundness=0, front=True):
 i=new_id()
 a={'type':'createFxRectLayer','compositionId':'main','layerId':i,'name':name,'activeRange':rng(start,end),'transform':tr(x,y),'rect':{'size':[w,h],'fillColor':color,'roundness':roundness}}
 if front:a['insertIndex']=0
 actions.append(a)
 return i

def image(name, asset, x, y, width, height, scale, start, end, animate=True):
 i=new_id()
 layer = {'type':'Image','id':i,'name':name,'blendMode':'normal','activeRange':rng(start,end),'transform':tr(x,y,(width/2,height/2),scale),'source':{'assetId':asset,'fit':'contain'}}
 if name == 'Pumpkin app icon': doc['composition']['layers'].insert(0, layer)
 else: doc['composition']['layers'].append(layer)
 if animate:entrance(i,end-start,y)
 return i

def audio(name, asset, start, duration, volume=0.7):
 i=new_id()
 doc['composition']['layers'].append({'type':'Audio','id':i,'name':name,'source':{'assetId':asset},'activeRange':rng(start,start+duration),'sourceRange':rng(0,duration),'sourceIntrinsicDuration':round(duration*1000),'volume':volume,'captionsEnabled':False})

# Imported images are behind the editable typography and shapes.
image('Brand illustration','pumpkin-art',800,450,1774,887,90.2,3,6,False)
image('Outro illustration','pumpkin-art',800,450,1774,887,90.2,16.5,21,False)
for name,asset,start,end in [('Download timer','download-panel',6,8.4),('Screenshot timer','screenshot-panel',8.4,10.5)]:
 image(name,asset,1125,460,816,562,86,start,end)
image('Real move-to-Trash panel','trash-panel',1125,460,816,270,86,10.5,13.5)
image('Real restore panel','restored-panel',1125,460,816,270,86,13.5,16.5)
image('Pumpkin app icon','app-icon',115,94,1024,1024,8,0,21,False)

# Backgrounds are behind all media. Native editable shapes, not raster slides.
rect('Forest opening',0,0,1600,900,green,0,3,front=False)
for s,e in [(6,10.5),(10.5,13.5),(13.5,16.5)]:rect('Cream demo background',0,0,1600,900,cream,s,e,front=False)
text('Brand header','PUMPKIN',166,73,500,55,26,0,3,cream,animate=False)
text('Brand header','PUMPKIN',166,73,500,55,26,3,21,green,animate=False)
text('Opening headline','Your Downloads\nfolder called.',100,235,700,240,76,0,3,cream,True)
text('Opening punchline','It wants its floor back.',105,475,650,100,34,0,3,[0.86,0.90,0.84,1])
text('Opening footnote','Too many files. One little pumpkin.',105,770,950,80,24,0,3,[0.86,0.90,0.84,1])

# Original file cards, grouped so each floats as one editable object.
for k,(name,x,y,rot) in enumerate([('final_FINAL.pdf',1070,250,-9),('Screenshot (42).png',1020,415,5),('Installer (7).dmg',1090,570,-4)]):
 b=rect('File card',x,y,380,120,[0.99,0.95,0.86,1],0,3,20)
 t=text('File card label',name,x+25,y+35,335,80,27,0,3,green,animate=False)
 g=new_id()
 actions.append({'type':'groupFxCompositionLayers','compositionId':'main','layerIds':[t,b],'groupLayerId':g,'name':name,'transform':tr(0,0)})
 entrance(g,3,0,delay=k*.10)
 actions.append({'type':'setFxPropertyAnimator','compositionId':'main','property':{'layerId':g,'propertyType':'rotation'},'animator':{'type':'jsScript','layerTimeJsCode':f'return {rot} + Math.sin(input.time.seconds * 2 + {k}) * 1.5;'},'dependencies':[]})

text('Brand introduction','Meet Pumpkin.',100,240,720,160,92,3,6,green,True)
text('Brand promise','A tiny menu bar app\nwith a tidy little habit.',105,400,610,180,34,3,6)
text('Brand annotation','Downloads + screenshots. On your schedule.',105,752,1000,70,25,3,6)

for start,end,label,title,body in [
 (6,10.5,'01 / PICK A TIME','Give it\nan expiry.','10 minutes, a day, a week…\nor keep it forever.'),
 (10.5,13.5,'02 / TIME’S UP','Bye, clutter.','Pumpkin moves expired files\nto the Trash automatically.'),
 (13.5,16.5,'03 / CHANGE YOUR MIND','Oops?\nPut it back.','Restore it from the Trash\nwith one click.')]:
 text('Step label',label,105,220,620,65,25,start,end,orange)
 text('Step headline',title,100,300,650,220,80,start,end,green,True)
 text('Step explanation',body,105,570,625,155,32,start,end)
 text('Demo context','Actual Pumpkin UI · Demo timers accelerated',105,810,1200,55,21,start,end,muted)

text('Outro name','Pumpkin',100,235,700,160,110,16.5,21,green,True)
text('Outro slogan','Every file gets\nits midnight.',105,415,630,170,49,16.5,21,green,True)
text('Outro availability','Free · Open source · macOS 14+',105,680,1000,70,26,16.5,21)
text('Outro CTA','Give your Downloads an exit plan.',105,768,1050,65,25,16.5,21,muted)
audio('Pumpkin arrival pop','pop',3.12,.3,.7)
audio('Expired file goodbye','goodbye',10.50,.65,.55)
audio('Restore ping','undo',13.55,.6,.6)

(WORK/'editable.json').write_text(json.dumps(doc,indent=2))
(WORK/'edits.json').write_text(json.dumps(actions,indent=2))
print(f'{len(doc["composition"]["layers"])} media layers, {len(actions)} native actions')
