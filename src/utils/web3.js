import Web3 from "web3";

export const getWeb3 = async () => {
  // Check if MetaMask is installed
  if (window.ethereum) {
    try {
      // Request account access
      await window.ethereum.request({ method: "eth_requestAccounts" });
      // Create Web3 instance
      const web3 = new Web3(window.ethereum);
      return web3;
    } catch (error) {
      console.error("User denied account access");
      throw error;
    }
  } else {
    throw new Error("MetaMask is not installed");
  }
};

export const getContract = async (web3, contractABI, contractAddress) => {
  try {
    console.log("Initializing contract with:", {
      web3: !!web3,
      contractABI: contractABI,
      contractAddress
    });

    if (!web3) {
      throw new Error("Web3 instance is not initialized");
    }

    if (!contractABI || !Array.isArray(contractABI)) {
      console.error("Invalid contract ABI:", contractABI);
      throw new Error("Invalid contract ABI");
    }

    if (!contractAddress) {
      throw new Error("Contract address is required");
    }

    // Create contract instance with the ABI
    const contract = new web3.eth.Contract(contractABI, contractAddress);
    
    return contract;
  } catch (error) {
    console.error("Error creating contract instance:", error);
    throw error;
  }
};