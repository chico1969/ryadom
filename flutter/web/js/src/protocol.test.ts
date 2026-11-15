import { decode, encode, idPk } from './protocol';
import schema from './schema.json';
import protobuf from 'protobufjs/light';
test('existing core messages and versioned control extension retain wire fields',()=>{
  const request={loginRequest:{username:'ПК',password:new Uint8Array([1,2,3]),myId:'browser-1',version:'1.5.3'}};
  expect(decode(encode(request)).loginRequest.username).toBe('ПК');
  expect(decode(encode({ryadomControl:{version:1,action:'transfer',target:7}})).ryadomControl.target).toBe(7);
});
test('identity uses the exact shared native protobuf definition',()=>{
  const type=protobuf.Root.fromJSON(schema).lookupType('hbb.IdPk');
  const bytes=type.encode(type.create({id:'ryadom-test',pk:new Uint8Array(32),dtlsFingerprint:'sha-256 AB:CD'})).finish();
  expect(idPk(bytes).dtlsFingerprint).toBe('sha-256 AB:CD');
});
test('large file sizes survive JSON and protobuf without rounding',()=>{
  const size='9007199254740993';
  const result=decode(encode({fileAction:{receive:{id:1,path:'C:\\папка',files:[{name:'файл',size}]}}}));
  expect(result.fileAction.receive.files[0].size).toBe(size);
});
