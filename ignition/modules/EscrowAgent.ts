import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const EscrowAgentModule = buildModule("EscrowAgentModule", (m) => {

  const escrow = m.contract("EscrowAgent");

  return { escrow };
});

export default EscrowAgentModule;
