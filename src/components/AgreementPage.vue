<template>
  <div class="agreement-page" :class="{ loading }">
    <div class="container">
      <header class="header">
        <div class="header-content">
          <div class="title-section">
            <h1>Multisig Escrow</h1>
            <p class="subtitle">Secure and transparent multisig escrow service</p>
          </div>
          <div class="connection-status">
            <div v-if="currentAccount" class="account-info">
              <span class="account-label">Account:</span>
              <span class="account-address">{{ formatAddress(currentAccount) }}</span>
            </div>
            <div class="status-indicator" :class="{ connected: isConnected }">
              <span class="status-dot" :class="{ connected: isConnected }">●</span>
              <span class="status-text">{{ isConnected ? 'Connected' : 'Disconnected' }}</span>
            </div>
            <button 
              v-if="!isConnected" 
              @click="connectWallet" 
              class="btn btn-connect"
              :disabled="loading"
            >
              Connect Wallet
            </button>
            <button 
              v-if="isConnected" 
              @click="disconnectWallet" 
              class="btn btn-disconnect"
              :disabled="loading"
            >
              Disconnect
            </button>
          </div>
        </div>
      </header>

      <div v-if="error" class="error-message">
        {{ error }}
      </div>

      <div class="content">
        <!-- Contract Deployment Form -->
        <div v-if="!deployedContract" class="card create-agreement">
          <h2>Deploy New Multisig Escrow</h2>
          <form @submit.prevent="deployContract" class="form">
            <div class="form-group">
              <label for="beneficiary">Beneficiary Address</label>
              <input 
                type="text" 
                v-model="beneficiary" 
                placeholder="0x..." 
                required 
                class="input"
                :disabled="loading"
              />
            </div>

            <div class="form-group">
              <label for="amount">Amount (ETH)</label>
              <input 
                type="number" 
                v-model="amount" 
                placeholder="0.1" 
                required 
                class="input"
                step="0.000000000000000001"
                min="0"
                :disabled="loading"
              />
            </div>

            <div class="form-group">
              <label for="deadline">Deadline</label>
              <input 
                type="datetime-local" 
                v-model="deadlineDate" 
                :min="getCurrentDateTime()"
                required 
                class="input"
                :disabled="loading"
                @change="updateDeadlineTimestamp"
              />
            </div>

            <div class="form-group">
              <label for="file">Agreement Document</label>
              <div class="file-upload-container">
                <input 
                  type="file" 
                  id="file"
                  ref="fileInput"
                  @change="handleFileUpload"
                  class="file-input"
                  :disabled="loading"
                />
                <div 
                  class="btn btn-upload"
                  :class="{ 'disabled': loading }"
                  @click="triggerFileInput"
                >
                  {{ selectedFile ? selectedFile.name : 'Choose File' }}
                </div>
                <div v-if="ipfsHash" class="ipfs-hash">
                  <span class="hash-label">IPFS Hash:</span>
                  <span class="hash-value">{{ ipfsHash }}</span>
                </div>
              </div>
            </div>

            <button 
              type="submit" 
              class="btn btn-primary"
              :disabled="loading"
            >
              {{ loading ? 'Deploying...' : 'Deploy Contract' }}
            </button>
          </form>
        </div>

        <!-- Contract Details View -->
        <div v-else class="card contract-details">
          <h2>Contract Details</h2>
          <div class="details-grid">
            <div class="detail-item">
              <span class="detail-label">Contract Address</span>
              <span class="detail-value">{{ formatAddress(deployedContract) }}</span>
            </div>
            <div class="detail-item">
              <span class="detail-label">Created Date</span>
              <span class="detail-value">{{ formatDate(contractDetails.startDate) }}</span>
            </div>
            <div class="detail-item">
              <span class="detail-label">Deadline</span>
              <span class="detail-value">{{ formatDate(contractDetails.deadlineDate) }}</span>
            </div>
            <div class="detail-item">
              <span class="detail-label">Value Locked</span>
              <span class="detail-value">{{ formatEth(contractDetails.amount) }} ETH</span>
            </div>
            <div class="detail-item">
              <span class="detail-label">Status</span>
              <span class="detail-value" :class="contractDetails.status.toLowerCase()">
                {{ contractDetails.status }}
              </span>
            </div>
            <div class="detail-item">
              <span class="detail-label">IPFS Document</span>
              <a 
                :href="`https://ipfs.io/ipfs/${contractDetails.detailsHash}`" 
                target="_blank"
                class="ipfs-link"
              >
                View Document
              </a>
            </div>
          </div>

          <!-- Available Actions -->
          <div class="actions-section">
            <h3>Available Actions</h3>
            <div class="actions-grid">
              <button 
                v-if="canApprove"
                @click="approveAgreement"
                class="btn btn-action"
                :disabled="loading"
              >
                Approve Agreement
              </button>
              <button 
                v-if="canReject"
                @click="rejectAgreement"
                class="btn btn-action"
                :disabled="loading"
              >
                Reject Agreement
              </button>
              <button 
                v-if="canRefund"
                @click="refundAgreement"
                class="btn btn-action"
                :disabled="loading"
              >
                Refund Agreement
              </button>
              <button 
                v-if="canRelease"
                @click="releaseFunds"
                class="btn btn-action"
                :disabled="loading"
              >
                Release Funds
              </button>
              <button 
                v-if="canWithdraw"
                @click="withdrawFunds"
                class="btn btn-action"
                :disabled="loading"
              >
                Withdraw Funds
              </button>
              <button 
                v-if="canRaiseDispute"
                @click="raiseDispute"
                class="btn btn-action"
                :disabled="loading"
              >
                Raise Dispute
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { getWeb3, getContract } from "../utils/web3";
import MultisigEscrowFactoryABI from "../../artifacts/contracts/MultisigEscrowFactory.sol/MultisigEscrowFactory.json";
import MultisigEscrowABI from "../../artifacts/contracts/MultisigEscrow.sol/MultisigEscrow.json";
import { create } from 'ipfs-http-client';
import './AgreementPage.css';

export default {
  data() {
    return {
      // Form data
      beneficiary: "",
      amount: "",
      deadlineDate: "",
      deadlineTimestamp: 0,
      
      // Contract state
      deployedContract: null,
      contractDetails: null,
      factoryContract: null,
      escrowContract: null,
      
      // Web3 state
      web3: null,
      isConnected: false,
      currentAccount: null,
      
      // File handling
      selectedFile: null,
      ipfsHash: null,
      ipfs: null,
      
      // UI state
      loading: false,
      error: null
    };
  },

  computed: {
    canApprove() {
      return this.contractDetails?.status === 'FUNDED' && 
             this.currentAccount === this.contractDetails.beneficiary;
    },
    canReject() {
      return this.contractDetails?.status === 'FUNDED' && 
             this.currentAccount === this.contractDetails.beneficiary;
    },
    canRefund() {
      return this.contractDetails?.status === 'ACTIVE' && 
             this.currentAccount === this.contractDetails.beneficiary;
    },
    canRelease() {
      return this.contractDetails?.status === 'ACTIVE' && 
             (this.currentAccount === this.contractDetails.beneficiary || 
              this.currentAccount === this.contractDetails.depositor);
    },
    canWithdraw() {
      return ['CLOSED', 'CANCELED', 'REJECTED', 'REFUNDED', 'RESOLVED', 'UNRESOLVED']
        .includes(this.contractDetails?.status);
    },
    canRaiseDispute() {
      return this.contractDetails?.status === 'ACTIVE' && 
             this.currentAccount === this.contractDetails.depositor &&
             Date.now() / 1000 > this.contractDetails.deadlineDate;
    }
  },

  methods: {
    async connectWallet() {
      try {
        this.loading = true;
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        this.currentAccount = accounts[0];
        this.isConnected = true;
        await this.initializeWeb3();
      } catch (error) {
        this.error = "Failed to connect wallet: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async initializeWeb3() {
      try {
        this.web3 = await getWeb3();
        this.factoryContract = await getContract(
          this.web3,
          MultisigEscrowFactoryABI,
          process.env.VUE_APP_FACTORY_ADDRESS
        );
      } catch (error) {
        this.error = "Failed to initialize Web3: " + error.message;
      }
    },

    async deployContract() {
      try {
        this.loading = true;
        if (!this.ipfsHash) {
          throw new Error("Please upload a document first");
        }

        const deadlineTimestamp = Math.floor(new Date(this.deadlineDate).getTime() / 1000);
        
        const tx = await this.factoryContract.methods.createEscrow(
          this.beneficiary,
          this.ipfsHash,
          deadlineTimestamp
        ).send({ 
          from: this.currentAccount,
          value: this.web3.utils.toWei(this.amount, 'ether')
        });

        this.deployedContract = tx.events.EscrowCreated.returnValues.escrow;
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to deploy contract: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async loadContractDetails() {
      try {
        this.escrowContract = await getContract(
          this.web3,
          MultisigEscrowABI,
          this.deployedContract
        );

        const details = await this.escrowContract.methods.getAgreementDetails().call();
        const status = await this.escrowContract.methods.getAgreementStatus().call();

        this.contractDetails = {
          depositor: details[0],
          beneficiary: details[1],
          amount: this.web3.utils.fromWei(details[2], 'ether'),
          startDate: parseInt(details[3]),
          deadlineDate: parseInt(details[4]),
          detailsHash: details[5],
          status: status
        };
      } catch (error) {
        this.error = "Failed to load contract details: " + error.message;
      }
    },

    async handleFileUpload(event) {
      try {
        this.loading = true;
        const file = event.target.files[0];
        if (!file) return;

        this.selectedFile = file;
        const added = await this.ipfs.add(file);
        this.ipfsHash = added.path;
      } catch (error) {
        this.error = "Failed to upload file: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    triggerFileInput() {
      this.$refs.fileInput.click();
    },

    getCurrentDateTime() {
      return new Date().toISOString().slice(0, 16);
    },

    formatAddress(address) {
      return `${address.slice(0, 6)}...${address.slice(-4)}`;
    },

    formatDate(timestamp) {
      return new Date(timestamp * 1000).toLocaleString();
    },

    formatEth(amount) {
      return parseFloat(amount).toFixed(4);
    },

    // Contract Actions
    async approveAgreement() {
      try {
        this.loading = true;
        await this.escrowContract.methods.approveAgreement().send({ from: this.currentAccount });
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to approve agreement: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async rejectAgreement() {
      try {
        this.loading = true;
        await this.escrowContract.methods.rejectAgreement().send({ from: this.currentAccount });
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to reject agreement: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async refundAgreement() {
      try {
        this.loading = true;
        await this.escrowContract.methods.refundAgreement().send({ from: this.currentAccount });
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to refund agreement: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async releaseFunds() {
      try {
        this.loading = true;
        await this.escrowContract.methods.releaseFunds().send({ from: this.currentAccount });
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to release funds: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async withdrawFunds() {
      try {
        this.loading = true;
        await this.escrowContract.methods.withdrawFunds().send({ from: this.currentAccount });
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to withdraw funds: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    async raiseDispute() {
      try {
        this.loading = true;
        await this.escrowContract.methods.raiseDispute().send({ from: this.currentAccount });
        await this.loadContractDetails();
      } catch (error) {
        this.error = "Failed to raise dispute: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    updateDeadlineTimestamp() {
      if (this.deadlineDate) {
        // Convert datetime-local value to Unix timestamp, accounting for timezone
        const date = new Date(this.deadlineDate);
        const timezoneOffset = date.getTimezoneOffset() * 60000;
        const adjustedDate = new Date(date.getTime() + timezoneOffset);
        this.deadlineTimestamp = Math.floor(adjustedDate.getTime() / 1000);
      }
    },

    async disconnectWallet() {
      try {
        this.loading = true;
        this.isConnected = false;
        this.currentAccount = null;
        this.web3 = null;
        this.factoryContract = null;
        this.escrowContract = null;
        this.selectedFile = null;
        this.ipfsHash = null;
        this.contractDetails = null;
      } catch (error) {
        this.error = "Failed to disconnect wallet: " + error.message;
      } finally {
        this.loading = false;
      }
    }
  },

  async created() {
    // Initialize IPFS client
    this.ipfs = create({ url: 'https://ipfs.infura.io:5001' });

    // Check if wallet is already connected
    if (window.ethereum) {
      const accounts = await window.ethereum.request({ method: 'eth_accounts' });
      if (accounts.length > 0) {
        this.isConnected = true;
        this.currentAccount = accounts[0];
        await this.initializeWeb3();
      }
    }
  }
};
</script>

<style>
/* Remove all styles as they are now in AgreementPage.css */
</style>