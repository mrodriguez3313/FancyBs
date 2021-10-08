// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// -------------
// FANCY BEE DAO
//
// This DAO esponsible for managing the treasury and all other contracts including:
//   - BeeNFT, HiveNFT, OutfitNFT and FancyBsGov (ERC20)
//
// All operations that involve a royalty toe the DAO must be mediated
// thought this contract.
//
// The DAO is goverened though the FancyBsGovenor contract and the FancyBsGov voting token.
// -------------


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./Royalty.sol";


contract FancyBsDAO is Ownable {
    
    struct hive{
        uint8 percent;
        uint256 balance;
    }
        
    mapping (address=> hive) public hiveMap;
    mapping (uint16=> address) public reverseHiveMap;
    
    uint16 hiveCount = 0;

    uint256 public treasury; //Amount to be distributed
    uint256 public retained; //Amount held for DAO
    uint256 public daoPercent;
    
    BeeNFT public beeNFT;
    HiveNFT public hiveNFT;//temp
    OutfitNFT public outfitNFT; 
    FancyBsGov public votingToken;
    FancyBsGovenor public governor; 
    
    constructor(){
        
        beeNFT = new BeeNFT();
        hiveNFT = new HiveNFT();
        votingToken = new FancyBsGov();
        governor = new FancyBsGovenor(votingToken);

    }
    
    // Allows the DAO to take ownership of the whole ecosystem.
    function LockOwnership() public onlyOwner {
        beeNFT.transferOwnership(address(this));
        hiveNFT.transferOwnership(address(this));
        votingToken.transferOwnership(address(this));
    }
    
    //Recieve all ETH there.  ERC20s are permissioned and accumulated in the ERC20 contract 
    receive() external payable {
        treasury += msg.value;
    }
    
    //
    // Interface to Beekeeper
    //
    //TODO
    //
    function dressMe(uint256 _beeID, uint256 _outfitID) public payable {
        require ( msg.value != 1^11, "Please send exactly x 100 GWei.");
        outfitNFT.attachToBee(_outfitID, address(beeNFT), _beeID);
        beeNFT.attachOutfit(_beeID, address(outfitNFT), _outfitID);
        treasury += msg.value;
    } 
    //
    // Interface to outfitNFT//
    //
    // TODO
    //
    
    //
    // Governance functions - these are functions that the Governance contract is able to call
    //
    
    function  distributeFunds(uint256 _amount) public onlyOwner{
        uint256 amt;
        
        if (_amount == 0 || _amount > treasury){
            amt = treasury;
        }
        //send the amounts.
        //TODO PROTECT RE-ENTRANCY!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        amt -= amt*10000/daoPercent;
        uint256 t = amt/hiveCount;
        for (uint16 i=0; i<hiveCount; i++){
            treasury -= t;
            (bool sent, bytes memory d) = reverseHiveMap[i].call{value: t}("");
            require(sent, "Failed to send Ether");
        }
        retained += treasury;
        treasury = 0;
    }
    
    function addCharity(address _addr) public onlyOwner{
        hiveMap[_addr].balance = 0;
        hiveMap[_addr].percent = 5; //default
        hiveCount++;
    }
    
    function setCharityPercent(address _addr, uint8 _p ) public onlyOwner{
        hiveMap[_addr].percent = _p; 
    }
    
    function setDAOPercent(uint8 _p) public onlyOwner{
        daoPercent = _p;
    }
}

// -------------
// FANCY BEE NFT
// -------------


contract BeeNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, Ownable, ERC721Burnable {
    
    address internal fancyDAO = msg.sender;
    
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    
    mapping (uint256=>address) outfitNFT;
    mapping (uint256=>uint256) outfitTokenID;

    constructor() ERC721("FancyBee", "FBEE") {}
    
    //TODO - register for ERC-1820
    function royaltyInfo(uint256 _tokenId, uint256 _price) external view returns (address receiver, uint256 amount){
        require (_tokenId>0, "TokenID out of range");
        return (fancyDAO, _price/10);
    }
    
    
    //==================================
    // SPECIAL FUNCIONALITY
    //
    function _tokenExists(uint256 _id) public view returns (bool){
        return (true); /// TODO we need to find the structure/map used by the framework.
    }
    // Called by the DAO to attach an outfit to a bee.
    function attachOutfit(uint256 _beeID, address _contract, uint256 _outfitID) public {
        require(msg.sender == fancyDAO, "Not fancyDAO");
        require (!_tokenExists(_beeID), "Invalid bee"); //check bee exists.
        require (!OutfitNFT(_contract)._tokenExists(_outfitID), "Invalid outfit"); //check the outfit exists
        require (OutfitNFT(_contract).isOwnedBy(_beeID), "Bee is not owner"); //check the outfit it ours
        _setTokenURI(_beeID, OutfitNFT(_contract).tokenURI(_outfitID)); //can we reference it?
        outfitNFT[_beeID] = _contract;
        outfitTokenID[_beeID] = _outfitID;
    }
    
    
    // Added from Marco's repo
    /*
    function mintToken(address owner, string memory metadataURI)
    public
    returns (uint256)
    {
        require( balanceOf(msg.sender) == 0, "Sorry, only one bee per person." );
        require( totalSupply() < totalBeeSupply, "Sorry only 5 are available at this time. ");
        _tokenIds.increment();

        uint256 id = _tokenIds.current();
        _safeMint(owner, id);
        _setTokenURI(id, metadataURI);

        return id;
    }*/
        
    //==================================
    
    
    //
    // Template behaviour...
    //

    function _baseURI() internal pure override returns (string memory) {
        return "IPFS://...";
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMint(address to) public onlyOwner {
        _safeMint(to, _tokenIdCounter.current());
        _tokenIdCounter.increment();
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }


}

// --------------
// FANCY HIVE NFT
// --------------


contract HiveNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, Ownable, ERC721Burnable {    
    
    address internal fancyDAO = msg.sender;
  
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("FancyHive", "FBHV") {}

    //
    //ALLOW ROYALTIES
    //TODO - register for ERC-1820
    //
    function royaltyInfo(uint256 _tokenId, uint256 _price) external view returns (address receiver, uint256 amount){
        require (_tokenId>0, "TokenID out of range");
        return (fancyDAO, _price/10);
    }

    //
    // SPECIAL FUNCIONALITY
    //
    function _tokenExists(uint256 _id) internal view returns (bool){
        return (true);
    }
    
    // Added from Marco's repo
    /* function mintToken(address owner, string memory metadataURI)
    public
    returns (uint256)
    {
        require( balanceOf(msg.sender) == 0, "Sorry, only one bee per person." );
        require( totalSupply() < totalBeeSupply, "Sorry only 5 are available at this time. ");
        _tokenIds.increment();

        uint256 id = _tokenIds.current();
        _safeMint(owner, id);
        _setTokenURI(id, metadataURI);

        return id;
    }*/
        
    //==================================
    //
    // Template behaviour...
    //
    
    function _baseURI() internal pure override returns (string memory) {
        return "IPFS://...";
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMint(address to) public onlyOwner {
        _safeMint(to, _tokenIdCounter.current());
        _tokenIdCounter.increment();
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}


// --------------
// FANCY OUTFIT NFT
// --------------


contract OutfitNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, Ownable, ERC721Burnable {    
    
    address internal fancyDAO = msg.sender;
  
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    
    mapping (uint256=>address) beeNFT;
    mapping (uint256=>uint256) beeTokenID;

    constructor() ERC721("FancyOutfit", "FBOF") {}

    //TODO - register for ERC-1820
    //TODO Should split it 50:50 with th creator. Register Outfit with as royalty receiver and split.
    function royaltyInfo(uint256 _tokenId, uint256 _price) external view returns (address receiver, uint256 amount){
        require (_tokenId>0, "TokenID out of range");
        return (fancyDAO, _price/10); //TODO need to forward price/5 to the creator.
    }

    //==================================
    // SPECIAL FUNCIONALITY
    //
    
    function _tokenExists(uint256 _id) public view returns (bool){
        return (true);
    }
    
    function isOwnedBy(uint256 _beeID) public view returns (bool){
        return(beeTokenID[_beeID] !=0);
    }
    // Called by the DAO to ask outfit to attach to a bee. Must be called _before_ calling the bee
    function attachToBee(uint256 _outfitID, address _contract, uint256  _beeID) public {
        require(msg.sender == fancyDAO, "Not fancyDAO");
        require (!_tokenExists(_outfitID), "Invalid outfit"); //check outfit exists.
        require (!BeeNFT(_contract)._tokenExists(_beeID), "Invalid bee"); //check the bee exists
        require (beeNFT[_outfitID] == address(0) || beeTokenID[_outfitID] == 0, "Already taken"); //check the outfit it available
        beeNFT[_outfitID] = _contract;
        beeTokenID[_outfitID] = _beeID;
        //  TODO _setTokenOWner(_contract, _beeID); //only the bee can control now (need better system)
        
    }
    
    // Added from Marco's repo
    /*
    function mintToken(address owner, string memory metadataURI)
    public
    returns (uint256)
    {
        require( balanceOf(msg.sender) == 0, "Sorry, only one bee per person." );
        require( totalSupply() < totalBeeSupply, "Sorry only 5 are available at this time. ");
        _tokenIds.increment();

        uint256 id = _tokenIds.current();
        _safeMint(owner, id);
        _setTokenURI(id, metadataURI);

        return id;
    }*/
        
    //==================================

    function _baseURI() internal pure override returns (string memory) {
        return "IPFS://...";
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function safeMint(address to) public onlyOwner {
        _safeMint(to, _tokenIdCounter.current());
        _tokenIdCounter.increment();
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    

}


// --------------------------
// FANCY BEE GOVERNANCE TOKEN
// --------------------------



contract FancyBsGov is ERC20, ERC20Burnable, ERC20Snapshot, Ownable, ERC20Permit, ERC20Votes {
    constructor() ERC20("FancyBsGov", "FBG") ERC20Permit("FancyBGov") {}
    
    address internal fancyDAO = msg.sender;

    function snapshot() public onlyOwner {
        _snapshot();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }
}


// -------------------------
// FANCY BEE VOTING GOVERNOR
// -------------------------


import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

contract FancyBsGovenor is Governor, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction  {
    
    address internal fancyDAO = msg.sender;
    
    constructor(ERC20Votes _token)
        Governor("FancyBsGovenor")
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)
    {}

    function votingDelay() public pure override returns (uint256) {
        return 1; // 1 block
    }

    function votingPeriod() public pure override returns (uint256) {
        return 45818; // 1 week
    }

    // The following functions are overrides required by Solidity.

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function getVotes(address account, uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotes)
        returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }
}
