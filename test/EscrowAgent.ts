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
      return { escrow, owner, depositor, beneficiary, someone };
    }

    async function createAgreementFixture() {
      const { escrow, owner, depositor, beneficiary, someone } = await loadFixture(deployEscrowFixture);
      const cid = "0xB45165ED3CD437B9FFAD02A2AAD22A4DDC69162470E2622982889CE5826F6E3D";
      const value = hre.ethers.parseEther("0.1");
      await escrow.connect(depositor)["createAgreement(address,string)"](beneficiary, cid, {value: value});
      const agreementId = 1;
      return { escrow, owner, depositor, beneficiary, someone, agreementId };
    }

    describe("Create agreement", () => {
        it("Should create a new agreement", async () => {
            const { escrow, owner, depositor, beneficiary } = await loadFixture(deployEscrowFixture);
            const cid = "0xB45165ED3CD437B9FFAD02A2AAD22A4DDC69162470E2622982889CE5826F6E3D";
            const value = hre.ethers.parseEther("0.1");
            const agreementId = 1;
            // check event with args
            const resp = await escrow.connect(depositor)["createAgreement(address,string)"](beneficiary, cid, {value: value});
            await expect(resp).to.emit(escrow, "AgreementCreated")
                .withArgs(depositor, beneficiary, agreementId, value, anyValue, cid);
            // check funds moved
            await expect(resp).to.changeEtherBalances(
                [depositor, escrow],
                [-value, value]
            );
            // status Funded
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(0);
            const defaultDeadline = 30 * 24 * 60 * 60;
            const start = Number(await time.latest());
            const end = Number(await time.increase(defaultDeadline));
            // check details
            const details = await escrow.connect(beneficiary).getAgreementDetails(agreementId);
            expect(details[0]).to.be.equal(cid);
            expect(details[1]).to.be.equal(value);
            expect(details[2].toString()).to.be.equal(start.toString());
            expect(details[3].toString()).to.be.equal(end.toString());
            // check funds moved
        });

        it("Should add funds to an existing agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            const value = hre.ethers.parseEther("0.01");
            // check event with args
            const resp = await escrow.connect(depositor).addFunds(agreementId, {value: value});
            await expect(resp).to.emit(escrow, "FundsAdded")
                .withArgs(agreementId, depositor, value, hre.ethers.parseEther("0.11"));
            // check funds moved
            await expect(resp).to.changeEtherBalances(
                  [depositor, escrow],
                  [-value, value]
                );
            // status should not change
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(0);
        });

        it("Should NOT add funds, access denied for other accounts", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            const value = hre.ethers.parseEther("0.01");
            // denied for beneficiary
            await expect(escrow.connect(beneficiary).addFunds(agreementId, {value: value})).to.revertedWith(
              "You are not the depositor."
            );
            // denied for others
            await expect(escrow.connect(someone).addFunds(agreementId, {value: value})).to.revertedWith(
              "You are not the depositor."
            );
        });
    });

  });