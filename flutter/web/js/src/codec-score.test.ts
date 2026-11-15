import {chooseMeasuredCodec} from './codec-score';
test('automatic codec uses actual responsiveness and traffic at fixed quality',()=>{
 const vp8={codec:'vp8',fps:30,delayMs:45,bytesPerSecond:1024*1024};
 expect(chooseMeasuredCodec([vp8,{codec:'vp9',fps:18,delayMs:50,bytesPerSecond:300000}])?.codec).toBe('vp8');
 expect(chooseMeasuredCodec([vp8,{codec:'vp9',fps:30,delayMs:45,bytesPerSecond:300000}])?.codec).toBe('vp9');
 expect(chooseMeasuredCodec([{codec:'vp8',fps:0,delayMs:10,bytesPerSecond:0}])).toBeUndefined();
});
