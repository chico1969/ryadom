import protobuf from 'protobufjs/light';
import schema from './schema.json';
const root = protobuf.Root.fromJSON(schema);
const message = root.lookupType('hbb.Message');
export type Wire = Record<string, any>;
export function encode(value: Wire): Uint8Array {
  const converted = message.fromObject(value);
  const error = message.verify(converted); if (error) throw new Error(error);
  return message.encode(converted).finish();
}
export function decode(bytes: Uint8Array): Wire {
  return message.toObject(message.decode(bytes), {longs:String,bytes:Uint8Array,oneofs:true});
}
export function idPk(bytes: Uint8Array): Wire {
  const type = root.lookupType('hbb.IdPk');
  return type.toObject(type.decode(bytes),{bytes:Uint8Array});
}
export function enumValue(type: string, name: string): number | undefined {
  return root.lookupEnum('hbb.' + type).values[name];
}
