// Validate the gameplay captures from either health smoke runner.
// PNGJS_MODULE may point to an existing pngjs installation.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
const {PNG}=createRequire(import.meta.url)(process.env.PNGJS_MODULE??'pngjs');
const directory=resolve(process.argv[2]??'build/health-native-validation');
const images={};
for(const name of ['healthy','low_health','recovered']) {
    images[name]=PNG.sync.read(readFileSync(join(directory,name+'.png')));
}
const {width,height}=images.healthy;
function chroma(image) {
    assert.equal(image.width,width);assert.equal(image.height,height);
    // Street/façades, excluding the HUD and most of the moving viewmodel.
    let sum=0,count=0;
    for(let y=Math.floor(height*.25);y<Math.floor(height*.75);y++) {
        for(let x=Math.floor(width*.2);x<Math.floor(width*.6);x++) {
            const i=(y*width+x)*4;
            const r=image.data[i],g=image.data[i+1],b=image.data[i+2];
            sum+=Math.max(r,g,b)-Math.min(r,g,b);count++;
        }
    }
    return sum/count;
}
const values=Object.fromEntries(Object.entries(images).map(([name,image])=>[name,chroma(image)]));
assert(values.healthy>5,'Fixture must contain coloured world geometry');
assert(values.low_health<values.healthy*.7,'Low health must visibly drain scene colour');
assert(Math.abs(values.recovered-values.healthy)<values.healthy*.08,'Recovery must restore scene colour');
const report={width,height,chroma:values,checks:3,
    scope:'Within-backend treatment/recovery gates; no cross-engine or exact-pixel parity claim.'};
writeFileSync(join(directory,'pixels.json'),JSON.stringify(report,null,2)+'\n');
console.log('PASS health pixels',JSON.stringify(report));
