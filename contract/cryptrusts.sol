// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CrypTrust
 * @dev A decentralized trust and escrow management system
 * @author CrypTrust Team
 */
contract CrypTrust {
    
    // State variables
    address public owner;
    uint256 public trustCounter;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 1; // 1% platform fee
    
    // Trust status enumeration
    enum TrustStatus {
        Active,
        Completed,
        Disputed,
        Cancelled
    }
    
    // Trust structure
    struct Trust {
        uint256 id;
        address trustor; // The person creating the trust
        address trustee; // The person receiving the trust
        address beneficiary; // The person who will benefit from the trust
        uint256 amount;
        uint256 releaseTime;
        TrustStatus status;
        string description;
        bool fundsReleased;
    }
    
    // Mappings
    mapping(uint256 => Trust) public trusts;
    mapping(address => uint256[]) public userTrusts;
    mapping(address => uint256) public balances;
    
    // Events
    event TrustCreated(
        uint256 indexed trustId,
        address indexed trustor,
        address indexed trustee,
        uint256 amount,
        uint256 releaseTime
    );
    
    event TrustCompleted(
        uint256 indexed trustId,
        address indexed beneficiary,
        uint256 amount
    );
    
    event TrustDisputed(
        uint256 indexed trustId,
        address indexed disputeInitiator
    );
    
    event FundsWithdrawn(
        address indexed user,
        uint256 amount
    );
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyTrustor(uint256 _trustId) {
        require(msg.sender == trusts[_trustId].trustor, "Only trustor can call this function");
        _;
    }
    
    modifier onlyTrustee(uint256 _trustId) {
        require(msg.sender == trusts[_trustId].trustee, "Only trustee can call this function");
        _;
    }
    
    modifier trustExists(uint256 _trustId) {
        require(_trustId > 0 && _trustId <= trustCounter, "Trust does not exist");
        _;
    }
    
    modifier trustActive(uint256 _trustId) {
        require(trusts[_trustId].status == TrustStatus.Active, "Trust is not active");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        trustCounter = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new trust
     * @param _trustee Address of the trustee
     * @param _beneficiary Address of the beneficiary
     * @param _releaseTime Timestamp when funds can be released
     * @param _description Description of the trust purpose
     */
    function createTrust(
        address _trustee,
        address _beneficiary,
        uint256 _releaseTime,
        string memory _description
    ) external payable returns (uint256) {
        require(msg.value > 0, "Trust amount must be greater than 0");
        require(_trustee != address(0), "Invalid trustee address");
        require(_beneficiary != address(0), "Invalid beneficiary address");
        require(_releaseTime > block.timestamp, "Release time must be in the future");
        require(bytes(_description).length > 0, "Description cannot be empty");
        
        trustCounter++;
        
        Trust memory newTrust = Trust({
            id: trustCounter,
            trustor: msg.sender,
            trustee: _trustee,
            beneficiary: _beneficiary,
            amount: msg.value,
            releaseTime: _releaseTime,
            status: TrustStatus.Active,
            description: _description,
            fundsReleased: false
        });
        
        trusts[trustCounter] = newTrust;
        userTrusts[msg.sender].push(trustCounter);
        userTrusts[_trustee].push(trustCounter);
        
        emit TrustCreated(trustCounter, msg.sender, _trustee, msg.value, _releaseTime);
        
        return trustCounter;
    }
    
    /**
     * @dev Core Function 2: Release trust funds to beneficiary
     * @param _trustId ID of the trust to release
     */
    function releaseTrust(uint256 _trustId) 
        external 
        trustExists(_trustId) 
        trustActive(_trustId) 
        onlyTrustee(_trustId) 
    {
        Trust storage trust = trusts[_trustId];
        
        require(block.timestamp >= trust.releaseTime, "Trust release time has not been reached");
        require(!trust.fundsReleased, "Funds have already been released");
        
        // Calculate platform fee
        uint256 platformFee = (trust.amount * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 beneficiaryAmount = trust.amount - platformFee;
        
        // Update trust status
        trust.status = TrustStatus.Completed;
        trust.fundsReleased = true;
        
        // Add funds to beneficiary balance
        balances[trust.beneficiary] += beneficiaryAmount;
        balances[owner] += platformFee;
        
        emit TrustCompleted(_trustId, trust.beneficiary, beneficiaryAmount);
    }
    
    /**
     * @dev Core Function 3: Dispute a trust
     * @param _trustId ID of the trust to dispute
     */
    function disputeTrust(uint256 _trustId) 
        external 
        trustExists(_trustId) 
        trustActive(_trustId) 
    {
        Trust storage trust = trusts[_trustId];
        
        require(
            msg.sender == trust.trustor || 
            msg.sender == trust.trustee || 
            msg.sender == trust.beneficiary,
            "Only involved parties can dispute the trust"
        );
        
        require(!trust.fundsReleased, "Cannot dispute after funds are released");
        
        trust.status = TrustStatus.Disputed;
        
        emit TrustDisputed(_trustId, msg.sender);
    }
    
    /**
     * @dev Resolve a disputed trust (only owner can resolve)
     * @param _trustId ID of the trust to resolve
     * @param _refundToTrustor Whether to refund to trustor (true) or release to beneficiary (false)
     */
    function resolveDispute(uint256 _trustId, bool _refundToTrustor) 
        external 
        onlyOwner 
        trustExists(_trustId) 
    {
        Trust storage trust = trusts[_trustId];
        
        require(trust.status == TrustStatus.Disputed, "Trust is not in disputed status");
        require(!trust.fundsReleased, "Funds have already been released");
        
        if (_refundToTrustor) {
            // Refund to trustor
            balances[trust.trustor] += trust.amount;
            trust.status = TrustStatus.Cancelled;
        } else {
            // Release to beneficiary
            uint256 platformFee = (trust.amount * PLATFORM_FEE_PERCENTAGE) / 100;
            uint256 beneficiaryAmount = trust.amount - platformFee;
            
            balances[trust.beneficiary] += beneficiaryAmount;
            balances[owner] += platformFee;
            trust.status = TrustStatus.Completed;
        }
        
        trust.fundsReleased = true;
    }
    
    /**
     * @dev Withdraw available balance
     */
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No funds available for withdrawal");
        
        balances[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit FundsWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Get trust details
     * @param _trustId ID of the trust
     */
    function getTrust(uint256 _trustId) 
        external 
        view 
        trustExists(_trustId) 
        returns (Trust memory) 
    {
        return trusts[_trustId];
    }
    
    /**
     * @dev Get all trusts associated with a user
     * @param _user Address of the user
     */
    function getUserTrusts(address _user) external view returns (uint256[] memory) {
        return userTrusts[_user];
    }
    
    /**
     * @dev Get user's available balance
     * @param _user Address of the user
     */
    function getBalance(address _user) external view returns (uint256) {
        return balances[_user];
    }
    
    /**
     * @dev Emergency function to pause contract (only owner)
     */
    function pauseContract() external onlyOwner {
        // Implementation for pausing contract functionality
        // This is a placeholder for emergency situations
    }
    
    /**
     * @dev Get contract statistics
     */
    function getContractStats() external view returns (
        uint256 totalTrusts,
        uint256 contractBalance,
        address contractOwner
    ) {
        return (trustCounter, address(this).balance, owner);
    }
}

