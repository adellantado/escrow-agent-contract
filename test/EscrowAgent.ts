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

    describe("Close agreement", () => {

        it("Beneficiary should refund agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            // check agreement refunded event
            await expect(await escrow.connect(beneficiary).refundAgreement(agreementId)).to.emit(escrow, "AgreementRefunded")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(4);
        });

        it("Depositor/others should NOT refund agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            // denied for depositor
            await expect(escrow.connect(depositor).refundAgreement(agreementId)).to.revertedWith(
              "You are not the beneficiary."
            );
            // denied for others
            await expect(escrow.connect(someone).refundAgreement(agreementId)).to.revertedWith(
              "You are not the beneficiary."
            );
        }); 

        it("Depositor should NOT close inactive agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId } = await loadFixture(createAgreementFixture);
            await expect(escrow.connect(depositor).releaseFunds(agreementId)).to.revertedWith(
              "The agreement is in a wrong status."
            );
        });

        it("Depositor should close agreement", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            // check funds released event
            await expect(escrow.connect(depositor).releaseFunds(agreementId)).to.emit(escrow, "FundsReleased")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(5);
        });

        it("Beneficiary should NOT close agreement before the deadline", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            await expect(escrow.connect(beneficiary).releaseFunds(agreementId)).to.revertedWith(
              "Funds will be released in 3 days after the deadline"
            );
        });

        it("Beneficiary should close agreement after the deadline + 3 days", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            const defaultDeadline = Number(await escrow.DEFAULT_DEADLINE_DATE());
            const threeDays = Number(await escrow.RELEASE_FUNDS_AFTER_DEADLINE());
            await time.increase(defaultDeadline + threeDays);
            // check funds released event
            await expect(escrow.connect(beneficiary).releaseFunds(agreementId)).to.emit(escrow, "FundsReleased")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(5);
        });
    });

    describe("Dispute agreement", () => {

        async function disputedAgreementFixture() {
            const { escrow, owner, depositor, beneficiary, someone, agreementId } = await loadFixture(activeAgreementFixture);
            const defaultDeadline = Number(await escrow.DEFAULT_DEADLINE_DATE());
            await time.increase(defaultDeadline);
            await escrow.connect(depositor).raiseDispute(agreementId);
            return { escrow, owner, depositor, beneficiary, someone, agreementId };
        }
      
        async function agreeOnArbitratorFixture() {
            const { escrow, owner, depositor, beneficiary, someone, agreementId } = await loadFixture(disputedAgreementFixture);
            const feePercentage = 0.1 * 1000000;
            const arbitrator = (await hre.ethers.getSigners())[4];
            await escrow.connect(depositor).registerArbitrator(agreementId, arbitrator, feePercentage);
            await escrow.connect(beneficiary).registerArbitrator(agreementId, arbitrator, feePercentage);
            return { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage };
        }

        it("Depositor should dispute agreement after the deadline", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            const defaultDeadline = Number(await escrow.DEFAULT_DEADLINE_DATE());
            await time.increase(defaultDeadline);
            // check dispute raised event
            await expect(escrow.connect(depositor).raiseDispute(agreementId)).to.emit(escrow, "DisputeRaised")
              .withArgs(agreementId);
            // status check
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(6);
        });

        it("Depositor should NOT dispute agreement before the deadline", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(activeAgreementFixture);
            // check revert before the deadline
            await expect(escrow.connect(depositor).raiseDispute(agreementId)).to.revertedWith(
              "You cannot raise dispute before the deadline"
            );
        });

        it("Depositor and beneficiary should agree on arbitrator", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(disputedAgreementFixture);
            const feePercentage = 0.1 * 1000000;
            const arbitrator = (await hre.ethers.getSigners())[4];
            // check agreed event 
            await expect(await escrow.connect(depositor).registerArbitrator(agreementId, arbitrator, feePercentage)).to.emit(escrow, "ArbitratorAgreed")
              .withArgs(agreementId, arbitrator, false);
            // check agreed event
            await expect(await escrow.connect(beneficiary).registerArbitrator(agreementId, arbitrator, feePercentage)).to.emit(escrow, "ArbitratorAgreed")
              .withArgs(agreementId, arbitrator, true);
        });

        it("Depositor and beneficiary should NOT agree on arbitrator's address", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(disputedAgreementFixture);
            const feePercentage = 0.1 * 1000000;
            const arbitrator1 = (await hre.ethers.getSigners())[4];
            const arbitrator2 = (await hre.ethers.getSigners())[5];
            // check agreed event
            await expect(await escrow.connect(depositor).registerArbitrator(agreementId, arbitrator1, feePercentage)).to.emit(escrow, "ArbitratorAgreed")
              .withArgs(agreementId, arbitrator1, false);
            // check revert on wrong address
            await expect(escrow.connect(beneficiary).registerArbitrator(agreementId, arbitrator2, feePercentage)).to.revertedWithCustomError(
              escrow, "WrongArbitrator"
            );
        });

        it("Depositor and beneficiary should NOT agree on arbitrator's fees", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(disputedAgreementFixture);
            const feePercentage1 = 0.1 * 1000000;
            const feePercentage2 = 0.12 * 1000000;
            const arbitrator = (await hre.ethers.getSigners())[4];
            // regiser an arbitrator
            await expect(await escrow.connect(depositor).registerArbitrator(agreementId, arbitrator, feePercentage1)).to.emit(escrow, "ArbitratorAgreed")
              .withArgs(agreementId, arbitrator, false);
            // check revert on wrong fees
            await expect(escrow.connect(beneficiary).registerArbitrator(agreementId, arbitrator, feePercentage2)).to.revertedWithCustomError(
              escrow, "WrongArbitrator"
            );
        });

        it("Should assign arbitrator from the pool after 'agree on arbitrator' period", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId} = await loadFixture(disputedAgreementFixture);
            const feePercentage = 0.1 * 1000000;
            const arbitrator = (await hre.ethers.getSigners())[4];
            // depositor vote on arbitrator
            await expect(await escrow.connect(depositor).registerArbitrator(agreementId, arbitrator, feePercentage)).to.emit(escrow, "ArbitratorAgreed")
              .withArgs(agreementId, arbitrator, false);
            const agreeOnArbitratorPeriod = Number(await escrow.AGREE_ON_ARBITRATOR_MAX_PERIOD());
            await time.increase(agreeOnArbitratorPeriod);
            // beneficiary vote on arbitrator after 'agree on arbitrator' period
            const res = await escrow.connect(beneficiary).registerArbitrator(agreementId, arbitrator, feePercentage);
            // check assigned event
            await expect(res).to.emit(escrow, "PoolArbitratorAssigned")
              .withArgs(agreementId, anyValue);
            // should nor raise the event
            await expect(res).to.not.emit(escrow, "ArbitratorAgreed");
        });

        it("Should assign arbitrator from the pool if the dispute wasn't resolved in 2 days by an agreed arbitrator", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage } = await loadFixture(agreeOnArbitratorFixture);
            const agreeOnArbitratorPeriod = Number(await escrow.AGREE_ON_ARBITRATOR_MAX_PERIOD());
            const resolveDisputePeriod = Number(await escrow.RESOLVE_DISPUTE_MAX_PERIOD());
            await time.increase(agreeOnArbitratorPeriod + resolveDisputePeriod);
            // check assigned event
            await expect(await escrow.connect(depositor).assignArbitrator(agreementId)).to.emit(escrow, "PoolArbitratorAssigned")
              .withArgs(agreementId, owner);
        });

        it("Should NOT assign arbitrator from the pool before 2 days after an arbitrator registered", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage } = await loadFixture(agreeOnArbitratorFixture);
            const agreeOnArbitratorPeriod = Number(await escrow.AGREE_ON_ARBITRATOR_MAX_PERIOD());
            await time.increase(agreeOnArbitratorPeriod);
            // check revert prohibiting assigning arbitrator from the pool
            await expect(escrow.connect(depositor).assignArbitrator(agreementId)).to.revertedWith(
              "Too early to assign artibrator from the pool"
            );
        });
      
        it("Arbitrator should resolve dispute", async () => {
          const { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage } = await loadFixture(agreeOnArbitratorFixture);
            const refundPercentage = 0.1 * 1000000;
            const value = hre.ethers.parseEther("0.1");
            const fee = hre.ethers.parseEther("0.01");
            const refund = hre.ethers.parseEther("0.009");
            const released = hre.ethers.parseEther("0.081");
            // check funds get distributed fully
            expect(fee + refund + released).to.be.equal(value);
            // check resolved event
            await expect(await escrow.connect(arbitrator)["resolveDispute(uint256,uint256)"](agreementId, refundPercentage)).to.emit(escrow, "DisputeResolved")
              .withArgs(agreementId, refundPercentage, fee, refund, released);
            // check status 
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(7);
        });

        it("Depositor/beneficiary should NOT resolve dispute", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage } = await loadFixture(agreeOnArbitratorFixture);
            const refundPercentage = 0.1 * 1000000;
            // check revert prohibiting resolving dispute for depositor with refund percentage
            await expect(escrow.connect(depositor)["resolveDispute(uint256,uint256)"](agreementId, refundPercentage)).to.revertedWith(
              "You are not the arbitrator."
            );
            // check revert prohibiting resolving dispute for beneficiary with refund percentage
            await expect(escrow.connect(beneficiary)["resolveDispute(uint256,uint256)"](agreementId, refundPercentage)).to.revertedWith(
              "You are not the arbitrator."
            );
            // check revert prohibiting resolving dispute for depositor by splitting funds
            await expect(escrow.connect(depositor)["resolveDispute(uint256)"](agreementId)).to.revertedWith(
              "You can resolve dispute yourself in 2 days after the pool arbitrator assignment date"
            );
            // check revert prohibiting resolving dispute for beneficiary by splitting funds
            await expect(escrow.connect(beneficiary)["resolveDispute(uint256)"](agreementId)).to.revertedWith(
              "You can resolve dispute yourself in 2 days after the pool arbitrator assignment date"
            );
        });

        it("Depositor/beneficiary should split escrow after assigned arbitrator isn't active for 2 days", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage } = await loadFixture(agreeOnArbitratorFixture);
            const value = hre.ethers.parseEther("0.1");
            const refund = value * await escrow.UNRESOLVED_DISPUTE_REFUND_PERCENTAGE() / 1_000_000n;
            const agreeOnArbitratorPeriod = Number(await escrow.AGREE_ON_ARBITRATOR_MAX_PERIOD());
            const resolveDisputePeriod = Number(await escrow.RESOLVE_DISPUTE_MAX_PERIOD());
            // wait before assigning pool arbitrator
            await time.increase(agreeOnArbitratorPeriod+resolveDisputePeriod);
            // check assigned event
            await expect(await escrow.connect(depositor).assignArbitrator(agreementId)).to.emit(escrow, "PoolArbitratorAssigned");
            // wait for pool arbitrator
            await time.increase(resolveDisputePeriod);
            // check unresolved event
            await expect(await escrow.connect(depositor)["resolveDispute(uint256)"](agreementId)).to.emit(escrow, "DisputeUnresolved")
              .withArgs(agreementId, Number(await escrow.UNRESOLVED_DISPUTE_REFUND_PERCENTAGE()), refund);
            // check status
            expect(await escrow.getAgreementStatus(agreementId)).to.be.equal(8);
        });

        it("Depositor/beneficiary should NOT split escrow before the 2 days resolvance deadline", async () => {
            const { escrow, owner, depositor, beneficiary, someone, agreementId, arbitrator, feePercentage } = await loadFixture(agreeOnArbitratorFixture);
            const value = hre.ethers.parseEther("0.1");
            const refund = value * await escrow.UNRESOLVED_DISPUTE_REFUND_PERCENTAGE() / 1_000_000n;
            const agreeOnArbitratorPeriod = Number(await escrow.AGREE_ON_ARBITRATOR_MAX_PERIOD());
            const resolveDisputePeriod = Number(await escrow.RESOLVE_DISPUTE_MAX_PERIOD());
            // wait before assigning pool arbitrator
            await time.increase(agreeOnArbitratorPeriod+resolveDisputePeriod);
            // check assigned event
            await expect(await escrow.connect(depositor).assignArbitrator(agreementId)).to.emit(escrow, "PoolArbitratorAssigned");
            // check revert
            await expect(escrow.connect(depositor)["resolveDispute(uint256)"](agreementId)).to.revertedWith(
              "You can resolve dispute yourself in 2 days after the pool arbitrator assignment date"
            );
        });
    });

  });