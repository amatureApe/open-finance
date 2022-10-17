// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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
    function rewardsToNative() external view returns (address[] memory);
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

interface IVaultHandler{
    function checkUser(address) external view returns (bool);
    function addUser(address) external;
}

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract OpenVault is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // The strategy in use by the vault.
    IStrategy public strategy;
    // The vaultHandler for this chain
    IVaultHandler public immutable vaultHandler;
    // The address that deployed this vault
    address public deployer = msg.sender;
    string public factoryId = Strings.toString(OpenVaultFactory(deployer).factoryId());

    // Bool to identify if strategy has been set and vault is active
    bool public active = false;

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'open' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     */
    constructor (
        address _vaultHandler,
        address _token
    ) ERC20(
        string(abi.encodePacked("Open ", ERC20(_token).name(), " factoryId-", factoryId)),
        string(abi.encodePacked("OPEN", ERC20(_token).symbol(),"-", factoryId))
    ) {
        vaultHandler = IVaultHandler(_vaultHandler);
    }

    // Modifier to check if strategy has been set and vault is active
    modifier isActive {
        require(active == true, "vault not active");
        _;
    }

    modifier checkUser {
        if (vaultHandler.checkUser(msg.sender) == true) {
            vaultHandler.addUser(msg.sender);
        }
        _;
    }

    // *********************************************
    // ********** MUTATIVE FUNCTIONS ***************
    // *********************************************

    function addStrategy(address _strategy) public {
      require(active == false, "vault already active");
      strategy = IStrategy(_strategy);
      require(msg.sender == strategy.strategist(), "not strategist");
      require(strategy.vault() == address(this), "incorrect vault");
      active = true;
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint _amount) public nonReentrant isActive checkUser {
        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balance();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        earn();
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public isActive {
        uint _bal = available();
        want().safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public nonReentrant isActive {
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint b = want().balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            strategy.withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        want().safeTransfer(msg.sender, r);
    }

    // ********************************
    // ********** VIEWS ***************
    // ********************************

    function want() public view isActive returns (IERC20) {
        return IERC20(strategy.want());
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view isActive returns (uint) {
        return want().balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view isActive returns (uint256) {
        return want().balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

}

contract OpenVaultFactory {
    // Mapping of all vaults launched by this factory contract.
   mapping(uint256 => OpenVault) public factoryVaults;
   // All factory vault Ids. These are not the same as Vault Ids on the
   // the Vault Handler. VaultId on Vault Handler correspond to successfully
   // added vaults.
   uint256 public factoryId = 0;
   // Address of vault handler
   address public immutable vaultHandler;

    constructor (
        address _vaultHandler
    ) {
        vaultHandler = _vaultHandler;
    }

   function CreateNewVault(address _token) public {
     OpenVault vault = new OpenVault(vaultHandler, _token);
     factoryVaults[factoryId] = vault;
     ++factoryId;
   }
}