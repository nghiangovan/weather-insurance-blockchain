pragma solidity >=0.5.0 <0.6.0;
pragma experimental ABIEncoderV2;

import "https://github.com/smartcontractkit/chainlink/blob/develop/evm-contracts/src/v0.5/ChainlinkClient.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/math/SafeMath.sol";
import "Strings.sol";
import "Integers.sol";

contract Evi is ChainlinkClient {
  using Strings for string;
  using Integers for uint;
    
  uint constant SECONDS_PER_DAY = 24 * 60 * 60;
  uint constant SECONDS_PER_HOUR = 60 * 60;
  int constant OFFSET19700101 = 2440588;
  
  using SafeMath_Chainlink for uint256;
  address private constant ORACLE_WEATHER = 0x4a3FBbB385b5eFEB4BC84a25AaADcD644Bd09721;
  bytes32 private constant JOB_ID_WEATHER = "a37ee8100c4c4ab19e30ae8039289b67";

  address private constant ORACLE_PRICE = 0xc99B3D447826532722E41bc36e644ba3479E4365;
  bytes32 private constant JOB_ID_PRICE = "3cff0a3524694ff8834bda9cf9c779a1";
  string[] public tempTimes = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23"];

  address payable manager;

  bool public paid = false;

  address payable buyer;
  string public location;
  string public date;
  string[] public times;
  string public timeString;
  uint256 public price;
  uint256 public rate;
  uint256 public linkAmount;
  uint public year;
  uint public month;
  uint public day;
  uint public hour;
  uint public expired;

  uint256 public totalRainyHours;
  uint256 public deploymentTime;
  uint256 public compensation;

  int256[] public hourlyState;

  uint256 public etherPrice;
  int256 public firstHours;
  bool public isQueryWeather = false;

  event successNodeResponse(
    bool success,
    int256 precipMM
  );

  event successPrice(
    bool success,
    uint256 price
  );

  uint256 public payment;

  constructor(
    address payable _buyer,
    string memory _location,
    string memory _date,
	string memory _times,
    uint256  _price,
    uint256  _rate,
    uint256 _linkAmount,
    address _link,
    address payable _manager) public payable {

    buyer = _buyer;
    location = _location;
    date = _date;
    price = _price;
	rate = _rate;
    linkAmount = _linkAmount;
    manager = _manager;

    bytes memory timesbyte = bytes(_times);
    for(uint i; i<24; i++){
      if(timesbyte[i] == "1") {
        times.push(tempTimes[i]);
        hour = i;
      }
    }
    
    timeString = _times;
    
    hour++;
    convertDateToArrayInt();
    expired = timestampFromDateTime(year, month, day, hour);

    deploymentTime = block.timestamp;

    if (_link == address(0)) {
      setPublicChainlinkToken();
      payment = 1 * LINK;
    } else {
      setChainlinkToken(_link);
      payment = 1;
    }

    setChainlinkOracle(ORACLE_WEATHER);
  }

  modifier buyerContract(){
    require(address(this) == msg.sender || buyer == msg.sender,"Unauthorised , must be buyer");
    _;
  }

  modifier onlyManager(){
	require(msg.sender == manager, "Unauthorised , must be manager");
	_;
  }
  
  function _daysFromDate(uint _year, uint _month, uint _day) internal pure returns (uint _days) {
    require(_year >= 1970);
    int _year_ = int(_year);
    int _month_ = int(_month);
    int _day_ = int(_day);

    int __days = _day_
      - 32075
      + 1461 * (_year_ + 4800 + (_month_ - 14) / 12) / 4
      + 367 * (_month_ - 2 - (_month_ - 14) / 12 * 12) / 12
      - 3 * ((_year_ + 4900 + (_month_ - 14) / 12) / 100) / 4
      - OFFSET19700101;

    _days = uint(__days);
  }
  
  function timestampFromDateTime(uint _year, uint _month, uint _day, uint _hour) public pure returns (uint _timestamp) {
    _timestamp = _daysFromDate(_year, _month, _day) * SECONDS_PER_DAY + _hour * SECONDS_PER_HOUR;
  }
  
    
  function convertDateToArrayInt() internal {
    string memory dateStr = "2020-05-13";
    string[] memory arrStr = dateStr.split("-");
    year = Integers.parseInt(arrStr[0]);
    month = Integers.parseInt(arrStr[1]);
    day = Integers.parseInt(arrStr[2]);
  }

  function queryPrice() public {
    Chainlink.Request memory req = buildChainlinkRequest(JOB_ID_PRICE, address(this), this.fulfillPrice.selector);
    req.add("get", "https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD");
    req.add("path", "USD");
  	req.addInt("times", 100);
    sendChainlinkRequestTo(ORACLE_PRICE, req, payment);
  }

  function fulfillPrice(bytes32 _requestId, uint256 _etherPrice) public recordChainlinkFulfillment(_requestId) {
    linkAmount--;
    emit successPrice(true, _etherPrice);
    etherPrice = _etherPrice;
  }

  function queryWeather() public {
    require(paid == false && isQueryWeather == false && now > expired);
    uint arrayLength = times.length;
    for (uint i=0; i<arrayLength; i++) {
      Chainlink.Request memory req = buildChainlinkRequest(JOB_ID_WEATHER, address(this), this.fulfillWeather.selector);
      req.add("q", location);
      req.add("date", date);
      req.add("tp", "1");
      bytes memory s;
      s = abi.encodePacked("data.weather.0.hourly.");
      s = abi.encodePacked(s, times[i]);
      s = abi.encodePacked(s, ".precipMM");
      string memory path = string(s);
      req.add("copyPath", path);
      req.addInt("times", 100);
      sendChainlinkRequestTo(chainlinkOracleAddress(), req, payment);
    }

    isQueryWeather = true;
  }

  function fulfillWeather(bytes32 _requestId, int256 _precipMM ) public recordChainlinkFulfillment(_requestId){
    linkAmount--;
    emit successNodeResponse(true, _precipMM);
    if(_precipMM >= 100){
      totalRainyHours++;
    }
    hourlyState.push(_precipMM);
  }

  function payInsurance() public payable onlyManager {
    require(paid == false);
    require(isQueryWeather == true);
    require(totalRainyHours > 0);

		compensation = (price * totalRainyHours / times.length) + price + (rate * price / 100);

		require(msg.value + address(this).balance >= compensation);
    buyer.transfer(compensation);
		paid = true;
  }

	function withDrawAllEther() public payable onlyManager {
		manager.transfer(address(this).balance);
	}

  function withDrawAllLINK() public onlyManager {
    require(linkAmount > 0);
    LinkTokenInterface link = LinkTokenInterface(0x20fE562d797A42Dcb3399062AE9546cd06f63280);
    link.transfer(manager, linkAmount * LINK);
    linkAmount = 0;
  }

  function getLINKBalance() public view onlyManager returns (uint256){
    return linkAmount;
  }

  function getBalance() public view returns (uint256){
	return address(this).balance;
  }
  
  function getDateNow() public view returns (bool){
	return now > expired;
  }
  
  function getChainlinkToken() public view returns (uint256) {
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    return link.balanceOf(address(this));   
  }
  
  

  function() external payable {}
}
