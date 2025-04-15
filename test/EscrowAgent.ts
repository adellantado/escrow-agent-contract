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

    async function activeAgreementFixture() {
      const { escrow, owner, depositor, beneficiary, someone, agreementId } = await loadFixture(createAgreementFixture);
      await escrow.connect(beneficiary).approveAgreement(agreementId);
      return { escrow, owner, depositor, beneficiary, someone, agreementId };
    }

    describe("Create agreement", () => {

        it("Should create a new agreement", async () => {
            const { escrow, owner, depositor, beneficiary } = await loadFixture(deployEscrowFixture);
            const cid = "0xB45165ED3CD437B9FFAD02A2AAD22A4DDC69162470E2622982889CE5826F6E3D";
            const value = hre.ethers.parseEther("0.1");
            const agreementId = 1;
            // check agreement created event
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
            const defaultDeadline = Number(await escrow.DEFAULT_DEADLINE_DATE());
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

        it("Depositor should add funds to an existing agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            const value = hre.ethers.parseEther("0.01");
            // check funds added event
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

        it("Beneficiary/others should NOT add funds", async () => {
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

    describe("Cancel, reject, approve agreement", () => {

        it("Depositor should cancel agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            // check agreement canceled event
            await expect(await escrow.connect(depositor).cancelAgreement(agreementId)).to.emit(escrow, "AgreementCanceled")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(1);
        });

        it("Beneficiary/others should NOT cancel agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            // denied for beneficiary
            await expect(escrow.connect(beneficiary).cancelAgreement(agreementId)).to.revertedWith(
              "You are not the depositor."
            );
            // denied for others
            await expect(escrow.connect(someone).cancelAgreement(agreementId)).to.revertedWith(
              "You are not the depositor."
            );
        });

        it("Beneficiary should reject agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            // check agreement rejected event
            await expect(await escrow.connect(beneficiary).rejectAgreement(agreementId)).to.emit(escrow, "AgreementRejected")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(2);
        });

        it("Depositor/others should NOT reject agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            // denied for depositor
            await expect(escrow.connect(depositor).rejectAgreement(agreementId)).to.revertedWith(
              "You are not the beneficiary."
            );
            // denied for others
            await expect(escrow.connect(someone).rejectAgreement(agreementId)).to.revertedWith(
              "You are not the beneficiary."
            );
        });

        it("Beneficiary should approve agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            // check agreement approved event
            await expect(await escrow.connect(beneficiary).approveAgreement(agreementId)).to.emit(escrow, "AgreementApproved")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(3);
        });

        it("Depositor/others should NOT approve agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(createAgreementFixture);
            // denied for depositor
            await expect(escrow.connect(depositor).approveAgreement(agreementId)).to.revertedWith(
              "You are not the beneficiary."
            );
            // denied for others
            await expect(escrow.connect(someone).approveAgreement(agreementId)).to.revertedWith(
              "You are not the beneficiary."
            );
        });     
    });

  });