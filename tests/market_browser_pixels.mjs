// Inspect the actual minimap pixels, catching lost parent coordinates/layers.
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
const {PNG}=createRequire(import.meta.url)(process.env.PNGJS_MODULE??'pngjs');
const directory=resolve(process.argv[2]??'build/full-market-browser-validation');
for(const name of ['north_plaza','east_alley','ruin_yard','cross_street','gate','e1_shop','e1_top','e3_room']) {
  const png=PNG.sync.read(readFileSync(resolve(directory,name+'.png')));
  if(png.width!==1280 || png.height!==720) throw new Error('Expected 1280x720: '+name);
  let floors=0,walls=0;
  for(let y=140;y<278;y++) for(let x=30;x<165;x++) {
    const i=(y*png.width+x)*4;
    const near=(r,g,b)=>Math.abs(png.data[i]-r)<4 && Math.abs(png.data[i+1]-g)<4 && Math.abs(png.data[i+2]-b)<4;
    if(near(38,54,59)) floors++;
    if(near(122,145,145)) walls++;
  }
  if(floors<1000 || walls<100) throw new Error(`${name}: missing minimap floor/wall geometry (${floors}/${walls})`);
  console.log('PASS minimap pixels',name,{floors,walls});
}
