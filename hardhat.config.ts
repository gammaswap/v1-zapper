import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "hardhat-contract-sizer"; // "npx hardhat size-contracts" or "yarn run hardhat size-contracts"

dotenv.config();

const config: HardhatUserConfig = {
  solidity: "0.8.21",
};

export default config;
