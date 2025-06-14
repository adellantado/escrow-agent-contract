<template>
  <div class="app">
    <header class="header">
      <div class="header-content">
        <div class="title-section">
          <h1>🔗 Multisig Escrow</h1>
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

    <main class="main-content">
      <!-- Initial View -->
      <InitView 
        v-if="isConnected && currentView === 'init'"
        @create-escrow="currentView = 'create_escrow'"
        @view-escrow="currentView = 'view_escrow'"
      />

      <!-- Create Escrow View -->
      <CreateEscrow
        v-if="isConnected && currentView === 'create_escrow'"
        :current-account="currentAccount"
        @escrow-created="handleEscrowCreated"
      />

      <!-- View Escrow -->
      <ViewEscrow
        v-if="isConnected && currentView === 'view_escrow'"
        :current-account="currentAccount"
        :escrow-address="currentEscrowAddress"
      />
    </main>
  </div>
</template>

<script>
import { getWeb3 } from "./utils/web3";
import InitView from './components/InitView.vue';
import CreateEscrow from './components/CreateEscrow.vue';
import ViewEscrow from './components/ViewEscrow.vue';

export default {
  name: 'App',
  components: {
    InitView,
    CreateEscrow,
    ViewEscrow
  },
  data() {
    return {
      currentView: 'init',
      isConnected: false,
      currentAccount: null,
      loading: false,
      error: null,
      currentEscrowAddress: null
    };
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
        await getWeb3();
      } catch (error) {
        this.error = "Failed to initialize Web3: " + error.message;
        console.error("Web3 initialization error:", error);
      }
    },

    async disconnectWallet() {
      try {
        this.loading = true;
        this.isConnected = false;
        this.currentAccount = null;
        this.currentView = 'init';
      } catch (error) {
        this.error = "Failed to disconnect wallet: " + error.message;
      } finally {
        this.loading = false;
      }
    },

    formatAddress(address) {
      return `${address.slice(0, 6)}...${address.slice(-4)}`;
    },

    handleEscrowCreated(escrowAddress) {
      this.currentEscrowAddress = escrowAddress;
      this.currentView = 'view_escrow';
    }
  },

  async created() {
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
.app {
  min-height: 100vh;
  background: #f5f5f5;
}

.header {
  background: white;
  padding: 1rem;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.header-content {
  max-width: 1200px;
  margin: 0 auto;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.title-section h1 {
  margin: 0;
  font-size: 1.5rem;
  color: #333;
}

.subtitle {
  margin: 0.5rem 0 0;
  color: #666;
  font-size: 0.9rem;
}

.connection-status {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.account-info {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.account-label {
  color: #666;
}

.account-address {
  font-family: monospace;
  color: #333;
}

.status-indicator {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.status-dot {
  color: #f44336;
}

.status-dot.connected {
  color: #4CAF50;
}

.status-text {
  color: #666;
}

.btn {
  padding: 0.5rem 1rem;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s ease;
  border: none;
  font-weight: 500;
}

.btn-connect {
  background: #4CAF50;
  color: white;
}

.btn-disconnect {
  background: #f44336;
  color: white;
}

.btn:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}

.error-message {
  background: #ffebee;
  color: #c62828;
  padding: 1rem;
  margin: 1rem;
  border-radius: 8px;
  text-align: center;
}

.main-content {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2rem 1rem;
}
</style>