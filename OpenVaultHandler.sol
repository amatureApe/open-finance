// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol";

interface IStrategy {
    function vault() external view returns (address);
    function strategist() external view returns (address);
    function maxFee() external view returns (uint256);
    function strategistFee() external view returns (uint256);
    function harvesterFee() external view returns (uint256);
    function stakerFee() external view returns (uint256);
    function want() external view returns (IERC20);
    function chef() external view returns (address);
    function poolId() external view returns (uint256);
    function rewardsToNative() external view returns (address[][] memory);
    function nativeToToken0() external view returns (address[] memory);
    function nativeToToken1() external view returns (address[] memory);
    function deposit() external;
    function withdraw(uint256) external;
    function balanceOf() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function harvest() external;
    function router() external view returns (address);
    function successfulHarvest() external view returns (bool);
}

interface IVault {
    function strategy() external view returns (address);
    function active() external view returns (bool);
    function deployer() external view returns (address);
    function factoryId() external view returns (uint256);
}

contract OpenVaultHandler is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Current vaultId index
    uint256 public vaultId = 0;
    // All vaults by their vaultId
    mapping(uint256 => Vault) public vaults;
    // All vaultInfos by their vaultId
    mapping(uint256 => VaultInfo) public vaultInfo;
    // Check to see if vault is already added
    mapping(address => bool) public addedVaults;

    // Current userId index
    uint256 public userId = 0;
    // All users by userId
    mapping(uint256 => User) public users;
    // Check to see if address has used OF before
    mapping(address => bool) public isUser;

    // Current commentId index
    uint256 public commentId = 0;
    // All vault comments by commentId
    mapping(uint256 => Comment) public comments;

    // current replyId index
    uint256 public replyId = 0;
    // All replies by replyId
    mapping(uint256 => Reply) public replies;

    // Vault deployer address
    address public vaultFactory;
    // Check to see if vaultDeployer has been set
    bool public vaultFactoryActive = false;

    mapping(uint256 => uint256) public factoryToVault;
    mapping(uint256 => uint256) public vaultToFactory;

    struct Vault {
        uint256 vaultId;
        address vault;
        address strategy;
        address want;
        address strategist;
        bytes description;
        Fees fees;
    }

    struct Fees {
        uint256 maxFee;
        uint256 strategistFee;
        uint256 harvesterFee;
        // uint256 stakerFee;
    }

    // Struct to manage likes, dislikes, and comments on vaults
    struct VaultInfo {
        uint256 vaultId;
        uint256 vaultLikes;
        uint256 vaultDislikes;
        uint256 totalCommentary;
    }

    struct User {
        uint256 userId;
        address userAddress;
        int256 reputation;
    }

    // Struct to manage comments on vaults
    struct Comment {
        uint256 vaultId;
        uint256 commentId;
        bytes comment;
        uint256 commentLikes;
        uint256 commentDislikes;
    }

    // Struct to manage replies to comments
    struct Reply {
        uint256 vaultId;
        uint256 commentId;
        uint256 replyId;
        bytes reply;
        uint256 replyLikes;
        uint256 replyDislikes;
    }

    // ******* MUTATIVE FUNCTIONS ***********
    function setVaultFactory(address _vaultFactory) external {
        require(vaultFactoryActive == false, "Vault deployer already active");
        vaultFactory = _vaultFactory;
        vaultFactoryActive = true;
    }

    function addVault(
        address _vault
    ) external returns (bool) {
        IVault vault = IVault(_vault);
        require(addedVaults[_vault] == false, "already added");
        require(vault.deployer() == vaultFactory, "not factory vault");

        address _strategy = vault.strategy();
        IStrategy strategy = IStrategy(_strategy);
        require(strategy.successfulHarvest() == true, "Need to successfully harvest");

        uint256 factoryId = vault.factoryId();
        address want = address(strategy.want());
        address strategist = strategy.strategist();

        uint256 maxFee = strategy.maxFee();
        uint256 strategistFee = strategy.strategistFee();
        uint256 harvesterFee = strategy.harvesterFee();
        // uint256 stakerFee = strategy.stakerFee();

        Fees memory _fees = Fees(
            maxFee,
            strategistFee,
            harvesterFee
            // stakerFee
        );

        Vault memory __vault = Vault(
            vaultId, // vaultId
            _vault,
            _strategy, // strategy address
            want, // want
            strategist, // strategist
            "",
            _fees
        );

        VaultInfo memory info;
        info.vaultId = vaultId;

        factoryToVault[factoryId] = vaultId;
        vaultToFactory[vaultId] = factoryId;

        vaults[vaultId] = __vault;
        vaultInfo[vaultId] = info;
        vaultId++;

        return true;
    }

    function addUser(address userAddress) external {
        User memory user = User(
            userId,
            userAddress,
            0
        );
        users[userId] = user;
        userId++;
    }

    function addDescription(uint256 _vaultId, string memory description) external {
        Vault storage vault = vaults[_vaultId];
        require(msg.sender == vault.strategist, "Not strategist");
        vault.description = bytes(description);
    }

    function likeVault(uint256 _vaultId) external {
        vaultInfo[_vaultId].vaultLikes++;
    }
    function dislikeVault(uint256 _vaultId) external {
        vaultInfo[_vaultId].vaultDislikes++;
    }

    function makeComment(uint256 _vaultId, string memory _comment) external {
        Comment memory comment = Comment(
            _vaultId,
            commentId,
            bytes(_comment),
            0,
            0
        );

        comments[commentId] = comment;
        commentId++;
        vaultInfo[_vaultId].totalCommentary++;
    }
    function likeComment(uint256 _commentId) external {
        Comment storage comment = comments[_commentId];
        comment.commentLikes++;
    }
    function dislikeComment(uint256 _commentId) external {
        Comment storage comment = comments[_commentId];
        comment.commentDislikes++;
    }

    function makeReply(uint256 _commentId, string memory _reply) external {
        uint256 _vaultId = comments[_commentId].vaultId;
        Reply memory reply = Reply(
            _vaultId,
            _commentId,
            replyId,
            bytes(_reply),
            0,
            0
        );
        replies[replyId] = reply;
        replyId++;
        vaultInfo[_vaultId].totalCommentary++;
    }
    function likeReply(uint256 _replyId) external {
        Reply storage reply = replies[_replyId];
        reply.replyLikes++;
    }
    function dislikeReply(uint256 _replyId) external {
        Reply storage reply = replies[_replyId];
        reply.replyDislikes++;
    }

    // ******* VIEWS *************

    function readDescription(uint256 _vaultId) external view returns (string memory) {
        Vault storage vault = vaults[_vaultId];
        return string(vault.description);
    }

    function readComment(uint256 _commentId) external view returns (string memory) {
        Comment storage comment = comments[_commentId];
        return string(comment.comment);
    }

    function readReply(uint256 _replyId) external view returns (string memory) {
        Reply storage reply = replies[_replyId];
        return string(reply.reply);
    }

    function checkUser(address _user) external view returns (bool) {
        return isUser[_user];
    }

    function factoryToVaultLookup(uint256 _factoryId) external view returns (uint256) {
        return factoryToVault[_factoryId];
    }

    function vaultToFactoryLookup(uint256 _vaultId) external view returns (uint256) {
        return vaultToFactory[_vaultId];
    }

}