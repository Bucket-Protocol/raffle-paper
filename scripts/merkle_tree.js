import { MerkleTree } from 'merkletreejs';

import { numToUint8Array } from './numToUint8Array.js';
import { sha3_256 } from './sha3_256.js';

function calculateHashByIndexAndAddress(index, address) {
  let bytesIndex = numToUint8Array(index);
  let hash_input = Buffer.concat([
    Buffer.from(bytesIndex),
    Buffer.from(address, 'hex'),
  ]);
  let hash_output = sha3_256(hash_input);
  return hash_output;
}

(async () => {
  let id = 6;
  let participantCount = 200;
  let address =
    '0xcba2aa3c7ee3f3f6580e78ba0008577867e20784bc5b3ad8f76db0ad4176f0e4';
  let addresses = Array(participantCount).fill(address);

  let leafs = [];
  for (let index = 0; index < addresses.length; index++) {
    let address = addresses[index];
    if (address.startsWith('0x')) {
      address = address.slice(2);
    }
    let hash_output = calculateHashByIndexAndAddress(index, address);
    leafs.push({
      index: index,
      address: address,
      hash: hash_output,
    });
  }
  let tree = new MerkleTree(
    leafs.map((x) => x.hash),
    sha3_256
  );

  let root = tree.getRoot().toString('hex');
  let proof = tree.getProof(leafs[id].hash);

  // console.log(leafs[0]);
  // console.log(proof.map((x) => x.data.toString('hex')));

  console.log(tree.verify(proof, leafs[id].hash, root)); // true
  proof = proof.map((x) => x.data.toString('hex'));
  console.log({ root, proof, leaf: leafs[id] });
})();
