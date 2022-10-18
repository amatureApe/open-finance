pragma solidity ^0.8.15;


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