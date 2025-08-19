// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FedRateProtection
 * @dev Smart Contract that references external JSON data source without Chainlink
 *
 * 🎯 LEARNING OBJECTIVE: Understand external data integration and oracle concepts
 *
 * 📋 SCENARIO:
 * - Contract explicitly references your JSON endpoint for transparency
 * - Instructor acts as oracle to bring JSON data into the contract
 * - Students can verify updates against the public JSON source
 * - Demonstrates why oracle services are needed in production
 *
 * 🔧 YOUR ROLE: You are the bank designing the protection product
 * 👤 INSTRUCTOR: Your client + oracle data provider
 * 🌐 JSON SOURCE: https://joannateo.github.io/fed-rate-demo/fed-rate.json
 */

contract FedRateProtection {

    // 📊 STUDENT CUSTOMIZABLE PARAMETERS
    // ═══════════════════════════════════════════════════════════════

    address public bank;                    // YOUR wallet address (the bank)
    address public client;                  // Client's wallet address (instructor)
    address public oracleOperator;          // Who can update rates (instructor)

    // 💰 LOAN AND COMPENSATION PARAMETERS (Student Configurable)
    uint256 public loanAmount;              // Original loan amount (YOU set this)
    uint256 public baselineRate;            // Starting Fed rate when contract created
    uint256 public triggerThreshold;        // Rate increase needed to trigger (YOU choose)
    uint256 public compensationRate;        // Compensation percentage (YOU choose)
    uint256 public currentFedRate;          // Current Fed rate from JSON

    // 🌐 JSON DATA SOURCE REFERENCE
    string public constant JSON_DATA_SOURCE = "https://joannateo.github.io/fed-rate-demo/fed-rate.json";
    string public constant JSON_FIELD_NAME = "current_rate";
    string public constant DATA_FORMAT = "Percentage (e.g., 4.50 for 5.00%)";
    uint256 public lastOracleUpdate;        // When was the rate last updated
    bool public oracleActive;               // Is the oracle currently active
    uint256 public oracleUpdateCount;       // How many times oracle has provided data

    // 📈 CONTRACT STATE
    bool public isActive;                   // Is the contract currently active?
    uint256 public totalCompensationPaid;   // Total amount paid to client
    uint256 public compensationCount;       // How many times we've paid compensation

    // 📝 TRANSACTION HISTORY
    struct CompensationEvent {
        uint256 timestamp;           // When the payment occurred
        uint256 oldRate;            // Previous Fed rate
        uint256 newRate;            // New Fed rate that triggered compensation
        uint256 rateIncrease;       // How much the rate increased
        uint256 compensationAmount;  // How much was paid
        string dataSource;          // Reference to JSON source
    }

    CompensationEvent[] public compensationHistory;

    struct OracleUpdate {
        uint256 timestamp;
        uint256 oldRate;
        uint256 newRate;
        address updater;
        string sourceReference;
    }

    OracleUpdate[] public oracleHistory;

    // 🔔 EVENTS
    event ContractCreated(
        address indexed bank,
        address indexed client,
        uint256 loanAmount,
        uint256 triggerThreshold,
        uint256 compensationRate,
        string jsonDataSource
    );

    event JSONRateUpdate(
        address indexed oracle,
        uint256 oldRate,
        uint256 newRate,
        uint256 timestamp,
        string jsonSource,
        string verificationMessage
    );

    event CompensationTriggered(
        address indexed client,
        uint256 oldRate,
        uint256 newRate,
        uint256 compensationAmount,
        string dataSourceReference
    );

    event CompensationNotTriggered(
        uint256 currentRate,
        uint256 baselineRate,
        uint256 threshold,
        string reason
    );

    event DataSourceVerification(
        string jsonUrl,
        string fieldName,
        uint256 contractRate,
        string instructions
    );

    // 🛡️ SECURITY MODIFIERS
    modifier onlyBank() {
        require(msg.sender == bank, "Only the bank can call this function");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleOperator, "Only the oracle can update rates");
        _;
    }

    modifier onlyActive() {
        require(isActive, "Contract is not active");
        require(oracleActive, "Oracle is not active");
        _;
    }

    // 🏗️ CONSTRUCTOR - STUDENT CUSTOMIZATION POINT
    // ═══════════════════════════════════════════════════════════════

    /**
     * @dev Create your Fed Rate Protection product with JSON data source reference
     *
     * 🎓 STUDENTS: Only 4 simple parameters to customize!
     * 🌐 JSON: Contract explicitly references external data source for transparency
     *
     * @param _clientAddress Client's wallet address (instructor address)
     * @param _loanAmount Original loan amount (e.g., 100000 for $100K)
     * @param _triggerThreshold Rate increase in basis points to trigger (e.g., 50 = 0.5%)
     * @param _compensationRate Compensation in basis points (e.g., 25 = 0.25%)
     */
    constructor(
        address _clientAddress,
        uint256 _loanAmount,
        uint256 _triggerThreshold,
        uint256 _compensationRate
    ) payable {
        // Validation
        require(_clientAddress != address(0), "Client address cannot be zero");
        require(_loanAmount > 0, "Loan amount must be positive");
        require(_triggerThreshold > 0 && _triggerThreshold <= 500, "Trigger must be 0.01% to 5%");
        require(_compensationRate > 0 && _compensationRate <= 1000, "Compensation must be 0.01% to 10%");

        // Set up YOUR contract parameters
        bank = msg.sender;                          // YOU are the bank
        client = _clientAddress;                    // Instructor is your client
        oracleOperator = 0x749e39c125347b366A0BFb4b3F76F34132804dED; // Fixed oracle address

        // YOUR loan product configuration (student customizable)
        loanAmount = _loanAmount;
        triggerThreshold = _triggerThreshold;
        compensationRate = _compensationRate;

        // Initialize with Fed rate (instructor will update from JSON)
        currentFedRate = 450;                       // Start at 4.50%
        baselineRate = currentFedRate;
        oracleActive = true;

        // Initialize state
        isActive = true;
        totalCompensationPaid = 0;
        compensationCount = 0;
        oracleUpdateCount = 0;
        lastOracleUpdate = block.timestamp;

        // Record initial oracle state
        oracleHistory.push(OracleUpdate({
            timestamp: block.timestamp,
            oldRate: 0,
            newRate: currentFedRate,
            updater: msg.sender,
            sourceReference: string(abi.encodePacked("Initial rate - Source: ", JSON_DATA_SOURCE))
        }));

        emit ContractCreated(bank, client, loanAmount, triggerThreshold, compensationRate, JSON_DATA_SOURCE);

        // Emit initial verification event
        emit DataSourceVerification(
            JSON_DATA_SOURCE,
            JSON_FIELD_NAME,
            currentFedRate,
            "Contract deployed - verify against JSON source"
        );
    }

    // 🌐 JSON-REFERENCED ORACLE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @dev Update Fed rate from JSON data source
     *
     * 🎛️ INSTRUCTOR: Call this with the current rate from the JSON endpoint!
     * 🌐 STUDENTS: This rate should match the JSON source - verify it!
     *
     * @param _newRate The current rate from the JSON (in basis points)
     */
    function updateFromJSONSource(uint256 _newRate) external onlyOracle onlyActive {
        require(_newRate >= 0 && _newRate <= 2000, "Rate must be between 0% and 20%");

        uint256 oldRate = currentFedRate;
        currentFedRate = _newRate;
        lastOracleUpdate = block.timestamp;
        oracleUpdateCount++;

        // Record oracle update with JSON reference
        oracleHistory.push(OracleUpdate({
            timestamp: block.timestamp,
            oldRate: oldRate,
            newRate: _newRate,
            updater: msg.sender,
            sourceReference: string(abi.encodePacked("Updated from JSON: ", JSON_DATA_SOURCE))
        }));

        emit JSONRateUpdate(
            msg.sender,
            oldRate,
            _newRate,
            block.timestamp,
            JSON_DATA_SOURCE,
            "Students: Verify this rate matches the JSON current_rate field!"
        );

        // Emit verification event for students
        emit DataSourceVerification(
            JSON_DATA_SOURCE,
            JSON_FIELD_NAME,
            _newRate,
            "Check JSON to verify this update is accurate"
        );

        // 🎯 CRITICAL: Check if YOUR compensation should be triggered
        checkAndTriggerCompensation(oldRate, _newRate);
    }

    /**
     * @dev Get instructions for verifying against JSON source
     *
     * 📋 STUDENTS: Use this to understand how to verify oracle updates!
     */
    function getJSONVerificationInstructions() external view returns (
        string memory step1,
        string memory step2,
        string memory step3,
        string memory jsonUrl,
        string memory fieldToCheck,
        uint256 currentContractRate
    ) {
        return (
            "1. Open the JSON URL in your browser",
            "2. Find the 'current_rate' field in the JSON data",
            "3. Compare JSON rate with contract rate (convert % to basis points: 5.25% = 525)",
            JSON_DATA_SOURCE,
            JSON_FIELD_NAME,
            currentFedRate
        );
    }

    /**
     * @dev Verify current contract rate matches external source
     *
     * 🔍 STUDENTS: Call this to see verification instructions and current state!
     */
    function verifyAgainstJSONSource() external view returns (
        string memory verificationMessage,
        string memory jsonUrl,
        uint256 contractRateInBasisPoints,
        string memory contractRateInPercent,
        string memory nextSteps
    ) {
        // Convert basis points to percentage string
        uint256 wholePart = currentFedRate / 100;
        uint256 decimalPart = currentFedRate % 100;
        string memory percentageDisplay = string(abi.encodePacked(
            toString(wholePart),
            ".",
            decimalPart < 10 ? "0" : "",
            toString(decimalPart),
            "%"
        ));

        return (
            "Check if contract rate matches JSON data source",
            JSON_DATA_SOURCE,
            currentFedRate,
            percentageDisplay,
            "If rates don't match, oracle update may be needed"
        );
    }

    /**
     * @dev Show the oracle process explanation
     *
     * 🎓 EDUCATIONAL: Explains why oracles are needed and how they work
     */
    function explainOracleProcess() external pure returns (
        string memory why,
        string memory how,
        string memory production,
        string memory currentSetup
    ) {
        return (
            "WHY: Smart contracts cannot directly access external URLs or APIs",
            "HOW: Oracle services fetch external data and bring it into the blockchain",
            "PRODUCTION: Services like Chainlink automatically monitor APIs and update contracts",
            "CURRENT SETUP: Instructor manually checks JSON and updates contracts for demonstration"
        );
    }

    // 💰 COMPENSATION LOGIC (Student's Custom Rules)
    // ═══════════════════════════════════════════════════════════════

    /**
     * @dev THE CORE LOGIC: Check if rate increase triggers compensation
     *
     * 🎯 STUDENTS: This is where YOUR custom protection rules execute!
     * 🌐 JSON: Data comes from your external JSON source
     */
    function checkAndTriggerCompensation(uint256 oldRate, uint256 newRate) internal {
        // 🔍 CRITICAL CHECK: Only trigger if rate increase exceeds YOUR threshold
        if (newRate > baselineRate + triggerThreshold) {
            // Calculate compensation: YOUR compensation rate * original loan amount
            uint256 compensationAmount = (loanAmount * compensationRate) / 10000;

            // Convert to wei for actual ETH transfer
            uint256 compensationInWei = compensationAmount * 1e12;

            // Check contract balance
            require(address(this).balance >= compensationInWei, "Insufficient contract balance");

            // 💰 EXECUTE THE PAYMENT AUTOMATICALLY
            (bool success, ) = payable(client).call{value: compensationInWei}("");
            require(success, "Transfer failed");

            // Update state
            totalCompensationPaid += compensationInWei;
            compensationCount++;

            // Record the event with JSON source reference
            compensationHistory.push(CompensationEvent({
                timestamp: block.timestamp,
                oldRate: oldRate,
                newRate: newRate,
                rateIncrease: newRate - baselineRate,
                compensationAmount: compensationInWei,
                dataSource: string(abi.encodePacked("Data from: ", JSON_DATA_SOURCE))
            }));

            emit CompensationTriggered(
                client,
                oldRate,
                newRate,
                compensationInWei,
                string(abi.encodePacked("Data from: ", JSON_DATA_SOURCE))
            );

            // Update baseline for future calculations
            baselineRate = newRate;
        } else {
            // 📊 IMPORTANT: Show when compensation does NOT trigger
            emit CompensationNotTriggered(
                newRate,
                baselineRate,
                triggerThreshold,
                string(abi.encodePacked(
                    "Rate increase of ", toString(newRate > baselineRate ? newRate - baselineRate : 0),
                    " basis points is below YOUR threshold of ", toString(triggerThreshold), " basis points"
                ))
            );
        }
    }

    // 📊 STUDENT ANALYSIS FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @dev Get YOUR simple contract configuration with JSON reference
     */
    function getMyContractDesign() external view returns (
        uint256 _loanAmount,
        uint256 _triggerThreshold,
        uint256 _compensationRate,
        string memory _dataSource,
        string memory _designSummary
    ) {
        string memory summary = string(abi.encodePacked(
            "Loan: $", toString(loanAmount), " | ",
            "Triggers at ", toString(triggerThreshold), " basis points increase | ",
            "Pays ", toString(compensationRate), " basis points compensation | ",
            "Data from JSON"
        ));

        return (
            loanAmount,
            triggerThreshold,
            compensationRate,
            JSON_DATA_SOURCE,
            summary
        );
    }

    /**
     * @dev Preview compensation with JSON source reference
     */
    function previewMyCompensation() external view returns (
        bool wouldTrigger,
        uint256 currentRateIncrease,
        uint256 compensationAmount,
        string memory status,
        string memory dataSource
    ) {
        uint256 rateIncrease = currentFedRate > baselineRate ? currentFedRate - baselineRate : 0;

        if (currentFedRate > baselineRate + triggerThreshold) {
            uint256 amount = (loanAmount * compensationRate) / 10000;
            return (
                true,
                rateIncrease,
                amount * 1e12, // Convert to wei
                string(abi.encodePacked(
                    "WOULD TRIGGER: Pay $", toString(amount), " (", toString(compensationRate),
                    "bp of $", toString(loanAmount), ")"
                )),
                JSON_DATA_SOURCE
            );
        } else {
            uint256 needed = (baselineRate + triggerThreshold) - currentFedRate;
            return (
                false,
                rateIncrease,
                0,
                string(abi.encodePacked(
                    "Need ", toString(needed), " more basis points to trigger (currently ",
                    toString(rateIncrease), "bp increase)"
                )),
                JSON_DATA_SOURCE
            );
        }
    }

    /**
     * @dev Get comprehensive contract status with data source info
     */
    function getContractStatus() external view returns (
        bool _isActive,
        bool _oracleActive,
        uint256 _currentFedRate,
        uint256 _baselineRate,
        uint256 _totalCompensationPaid,
        uint256 _compensationCount,
        uint256 _contractBalance,
        uint256 _nextTriggerRate,
        string memory _dataSource
    ) {
        return (
            isActive,
            oracleActive,
            currentFedRate,
            baselineRate,
            totalCompensationPaid,
            compensationCount,
            address(this).balance,
            baselineRate + triggerThreshold,
            JSON_DATA_SOURCE
        );
    }

    /**
     * @dev Get oracle information with JSON source reference
     */
    function getOracleInfo() external view returns (
        string memory _jsonDataSource,
        string memory _jsonFieldName,
        address _oracleOperator,
        uint256 _oracleUpdateCount,
        uint256 _lastOracleUpdate
    ) {
        return (
            JSON_DATA_SOURCE,
            JSON_FIELD_NAME,
            oracleOperator,
            oracleUpdateCount,
            lastOracleUpdate
        );
    }

    /**
     * @dev Get compensation history with JSON source references
     */
    function getCompensationHistory() external view returns (CompensationEvent[] memory) {
        return compensationHistory;
    }

    /**
     * @dev Get oracle update history with JSON references
     */
    function getOracleHistory() external view returns (OracleUpdate[] memory) {
        return oracleHistory;
    }

    // 🛠️ ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @dev Add more funds for compensation payments
     */
    function addFunds() external payable onlyBank {
        require(msg.value > 0, "Must send some ETH");
    }

    /**
     * @dev Emergency deactivation
     */
    function deactivateContract() external onlyBank {
        isActive = false;
    }

    /**
     * @dev Withdraw remaining funds (only when inactive)
     */
    function withdrawRemainingFunds() external onlyBank {
        require(!isActive, "Contract must be deactivated first");
        payable(bank).transfer(address(this).balance);
    }

    // 🎯 HELPER FUNCTIONS
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
