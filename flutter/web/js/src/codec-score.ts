export type CodecMeasurement = {codec:string;fps:number;delayMs:number;bytesPerSecond:number};
export function chooseMeasuredCodec(trials:CodecMeasurement[]):CodecMeasurement|undefined {
  const usable=trials.filter(t=>Number.isFinite(t.fps)&&t.fps>=3&&Number.isFinite(t.delayMs)&&t.delayMs>=0&&Number.isFinite(t.bytesPerSecond));
  const score=(t:CodecMeasurement)=>Math.min(t.fps,60)*4-Math.min(t.delayMs,1000)*.08-Math.max(0,t.bytesPerSecond)/(1024*1024)*2;
  return usable.reduce<CodecMeasurement|undefined>((best,value)=>!best||score(value)>score(best)?value:best,undefined);
}
