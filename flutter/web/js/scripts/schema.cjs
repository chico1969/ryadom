const fs = require('node:fs');
const path = require('node:path');
const protobuf = require('protobufjs');
const schema = path.resolve(__dirname, '../../../../libs/base/protos/message.proto');
const identity = path.resolve(__dirname, '../../../../libs/hbb_common/protos/rendezvous.proto');
fs.writeFileSync(path.resolve(__dirname, '../src/schema.json'), JSON.stringify(protobuf.loadSync([schema, identity]).toJSON()));
