import { keyEvent } from './keyboard';
const key=(value:string,ctrlKey=false)=>({key:value,ctrlKey,altKey:false,metaKey:false,shiftKey:false});
test('Cyrillic text uses Unicode, shortcut letters use key down/up',()=>{
  expect(keyEvent(key('Ж'))).toMatchObject({unicode:1046,press:true});
  expect(keyEvent(key('c',true))).toMatchObject({chr:99,down:true,modifiers:[4]});
  expect(keyEvent(key('Enter'))).toMatchObject({controlKey:27,down:true});
  expect(keyEvent(key('ArrowLeft'))).toMatchObject({controlKey:22,down:true});
  expect(keyEvent(key('Unidentified'))).toBeUndefined();
  expect(keyEvent({...key('с',true),code:'KeyC'})).toMatchObject({chr:99,down:true,modifiers:[4]});
  expect(keyEvent({...key('@',true),altKey:true,code:'KeyQ',getModifierState:()=>true})).toMatchObject({unicode:64,press:true,modifiers:[]});
});
