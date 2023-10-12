import * as bls from '@noble/bls12-381';

import crypto from 'node:crypto';
import { sha3_256 } from './sha3_256.js';
function numToHex(num) {
  let time = BigInt(num);
  let timeBuffer = Buffer.alloc(8);
  timeBuffer.writeBigUInt64LE(time);
  return timeBuffer.toString('hex');
}

(async () => {
  // keys, messages & other inputs can be Uint8Arrays or hex strings
  let privateKey =
    '67d53f170b908cabb9eb326c3c337762d59289a8fec79f7bc9254b584b73265c';
  let user_seed = await sha3_256('RANDOM');

  let time = 1687975971000;
  console.log(user_seed);
  console.log(numToHex(time));
  let message = user_seed + numToHex(time);
  console.log('message', message);

  let publicKey = bls.getPublicKey(privateKey);
  let signature = await bls.sign(message, privateKey);
  let isValid = await bls.verify(signature, message, publicKey);

  // Convert to hex strings
  let publicKeyHex = Buffer.from(publicKey).toString('hex');
  let signatureHex = Buffer.from(signature).toString('hex');
  let messageHex = Buffer.from(message).toString('hex');

  console.log({ publicKeyHex, signatureHex, messageHex, isValid });
})();
