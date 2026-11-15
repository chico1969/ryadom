import { enumValue, Wire } from './protocol';
const names:Record<string,string>={Enter:'Return',ArrowUp:'UpArrow',ArrowDown:'DownArrow',ArrowLeft:'LeftArrow',ArrowRight:'RightArrow',' ':'Space'};
export function keyEvent(e:Pick<KeyboardEvent,'key'|'altKey'|'ctrlKey'|'metaKey'|'shiftKey'>&{code?:string;getModifierState?:(name:string)=>boolean}):Wire|undefined {
  const modifiers=[e.altKey?1:0,e.ctrlKey?4:0,e.metaKey?23:0,e.shiftKey?29:0].filter(Boolean);
  const controlKey=enumValue('ControlKey',names[e.key]??e.key);
  if(controlKey)return {controlKey,down:true,modifiers,mode:0};
  if([...e.key].length!==1)return;
  if(e.getModifierState?.('AltGraph'))return {unicode:e.key.codePointAt(0),press:true,modifiers:[],mode:0};
  if(e.ctrlKey||e.altKey||e.metaKey){
    const physical=/^Key([A-Z])$/.exec(e.code??'')?.[1]?.toLowerCase();
    return {chr:(physical??e.key).codePointAt(0),down:true,modifiers,mode:0};
  }
  return {unicode:e.key.codePointAt(0),press:true,modifiers,mode:0};
}
