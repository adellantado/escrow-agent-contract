import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre from "hardhat";


  describe("EscrowAgent", function () {

    async function deployEscrowFixture() {
      const [owner, depositor, beneficiary, someone] = await hre.ethers.getSigners();
  
      const EscrowAgent = await hre.ethers.getContractFactory("EscrowAgent");
      const escrow = await EscrowAgent.deploy();
  
      return { escrow, owner, depositor, beneficiary, };
    }

    describe("Create agreement", () => {
        it("Should create a new agreement", async () => {
            const { escrow, owner, depositor, beneficiary } = await loadFixture(deployEscrowFixture);
            const cid = "0xB45165ED3CD437B9FFAD02A2AAD22A4DDC69162470E2622982889CE5826F6E3D";
            const value = hre.ethers.parseEther("0.1");
            const agreementId = 1;
            
            await expect(await escrow.connect(depositor)["createAgreement(address,string)"](beneficiary, cid, {value: value})).to.emit(escrow, "AgreementCreated")
                .withArgs(depositor, beneficiary, agreementId, value, anyValue, cid);
            
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(0);

            const defaultDeadline = 30 * 24 * 60 * 60;
            const start = Number(await time.latest());
            const end = Number(await time.increase(defaultDeadline));

            const details = await escrow.connect(beneficiary).getAgreementDetails(agreementId);
            expect(details[0]).to.be.equal(cid);
            expect(details[1]).to.be.equal(value);
            expect(details[2].toString()).to.be.equal(start.toString());
            expect(details[3].toString()).to.be.equal(end.toString());
        });
    })




  });