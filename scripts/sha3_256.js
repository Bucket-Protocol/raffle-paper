import { createHash } from "crypto";

function sha3_256(input) {
  return createHash("sha3-256").update(Buffer.from(input)).digest("hex");
}

export { sha3_256 };
