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
}

interface IVault {
    function strategy() external view returns (address);
    function active() external view returns (bool);
}

contract OpenVaultHandler is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Current vaultId index
    uint256 public vaultId = 0;
    // All vaults by their vaultId
    mapping(uint256 => Vault) public vaults;
    // All vaultInfos by their vaultId
    mapping(uint256 => VaultInfo) public vaultInfo;

    // Current commentId index
    uint256 public commentId = 0;
    // All vault comments by commentId
    mapping(uint256 => Comment) public comments;

    // current replyId index
    uint256 public replyId = 0;
    // All replies by replyId
    mapping(uint256 => Reply) public replies;



    // Vault types according to their interface compatibility i.e. UniV2, Curve, Balancer, etc.
    mapping(uint256 => string) public vaultTypes;
    // Contract that distributes rewards
    mapping(uint256 => address) public chefs;

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
        uint256 stakerFee;
    }

    // Struct to manage likes, dislikes, and comments on vaults
    struct VaultInfo {
        uint256 vaultId;
        uint256 VaultLikes;
        uint256 VaultDislikes;
    }

    // Struct to manage comments on vaults
    struct Comment {
        uint256 vaultId;
        uint256 commentId;
        string comment;
        uint256 commentLikes;
        uint256 commentDislikes;
    }

    // Struct to manage replies to comments
    struct Reply {
        uint256 commentId;
        uint256 replyId;
        string reply;
        uint256 replyLikes;
        uint256 replyDislikes;
    }

    // ******* MUTATIVE FUNCTIONS ***********
    function addVault(
        address _vault
    ) external returns (bool) {
        IVault vault = IVault(_vault);
        require(vault.active() == true, "vault not active");

        address _strategy = vault.strategy();
        IStrategy strategy = IStrategy(_strategy);

        address want = address(strategy.want());
        address strategist = strategy.strategist();

        uint256 maxFee = strategy.maxFee();
        uint256 strategistFee = strategy.strategistFee();
        uint256 harvesterFee = strategy.harvesterFee();
        uint256 stakerFee = strategy.stakerFee();

        Fees memory _fees = Fees(
            maxFee,
            strategistFee,
            harvesterFee,
            stakerFee
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

        vaults[vaultId] = __vault;
        vaultInfo[vaultId] = info;
        vaultId++;

        return true;
    }

    function addDescription(uint256 _vaultId, string memory description) external {
        Vault storage vault = vaults[_vaultId];
        require(msg.sender == vault.strategist, "Not strategist");
        vault.description = bytes(description);
    }

    function likeVault(uint256 _vaultId) external {
        vaultInfo[_vaultId].VaultLikes++;
    }
    function dislikeVault(uint256 _vaultId) external {
        vaultInfo[_vaultId].VaultDislikes++;
    }

    function makeComment(uint256 _vaultId, string memory _comment) external {
        Comment memory comment = Comment(
            _vaultId,
            commentId,
            _comment,
            0,
            0
        );

        comments[commentId] = comment;
        commentId++;
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
        Reply memory reply = Reply(
            _commentId,
            replyId,
            _reply,
            0,
            0
        );
        replies[replyId] = reply;
        replyId++;
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

    // function balance(uint256 _vaultId) public view returns (uint) {
    //   return want().balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    // }

    function readDescription(uint256 _vaultId) external view returns (string memory) {
        Vault storage vault = vaults[_vaultId];
        return string(vault.description);
    }

}