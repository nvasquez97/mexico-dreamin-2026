/**
 * @description Shared test data builders for RutaCargo. Builders return UNSAVED
 *              records with every required field set, so each test decides when
 *              to insert and which fields to override.
 */
@IsTest
public with sharing class TestDataFactory {

    public static final String DEFAULT_ACCOUNT_NAME = 'Test Customer';
    public static final String PLATFORM_PROFILE_NAME = 'Standard Platform User';
    public static final String INTEGRATION_PROFILE_NAME = 'Minimum Access - API Only Integrations';
    public static final String API_INTEGRATION_PSL = 'SalesforceAPIIntegrationPsl';
    public static final String ENTREGAYA_PERMISSION_SET = 'RutaCargo_EntregaYa_Integration';
    public static final String ENTREGAYA_GROUP = 'RutaCargo_EntregaYa_Integration';
    public static final String AGENT_PERMISSION_SET = 'RutaCargo_Support_Agent';
    public static final String AGENT_GROUP = 'RutaCargo_Support_Agents';
    public static final String RULE_ACCESS = 'Edit';
    public static final String SITE_GUEST_PROFILE_NAME = 'RutaCargo Profile';

    /**
     * @description When true, newOrExistingIntegrationUser must reuse an existing
     *              integration user and throws TestDataException instead of
     *              building a new one. Tests set it to force the reuse branch.
     */
    @TestVisible
    private static Boolean reuseExistingIntegrationUserOnly = false;

    /** @description Thrown when the factory cannot build the requested test data. */
    public class TestDataException extends Exception {}

    // ─── Accounts (customers) ─────────────────────────────────────────────

    public static Account newCustomerAccount(String name) {
        return new Account(
            Name = name,
            Customer_Type__c = 'Business',
            Credit_Limit__c = 100000,
            Credit_Risk__c = 'Low'
        );
    }

    public static Account newCustomerAccount() {
        return newCustomerAccount(DEFAULT_ACCOUNT_NAME);
    }

    // ─── Shipments ────────────────────────────────────────────────────────

    /**
     * @description Unsaved shipment for the given customer. Status__c is left
     *              empty on purpose so the field default applies on insert.
     */
    public static Shipment__c newShipment(Id accountId) {
        return new Shipment__c(
            Account__c = accountId,
            Service_Type__c = 'Standard',
            Pickup_Address__c = 'Av. Reforma 100, Col. Juarez',
            Pickup_Postal_Code__c = '06600',
            Pickup_Date__c = Date.newInstance(2026, 12, 1),
            Origin_City__c = 'Ciudad de Mexico',
            Destination_City__c = 'Guadalajara',
            Recipient_Name__c = 'Test Recipient',
            Recipient_Address__c = 'Av. Vallarta 200, Col. Americana',
            Destination_Postal_Code__c = '44160',
            Recipient_Phone__c = '+52 33 0000 0000',
            Recipient_Email__c = 'recipient@example.com',
            Package_Description__c = 'Test package',
            Weight_Kg__c = 1.5
        );
    }

    public static List<Shipment__c> newShipments(Id accountId, Integer count) {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < count; i++) {
            shipments.add(newShipment(accountId));
        }
        return shipments;
    }

    // ─── Users ────────────────────────────────────────────────────────────

    /**
     * @description Unsaved internal user with the given profile. The username is
     *              made unique with the org id and the given key.
     * @param profileId the profile of the user
     * @param uniqueKey a short key (letters and digits) that makes the user unique in the test
     * @return the unsaved user
     */
    public static User newUser(Id profileId, String uniqueKey) {
        return new User(
            ProfileId = profileId,
            LastName = 'Test ' + uniqueKey,
            Alias = uniqueKey.left(8),
            Email = uniqueKey + '@example.com',
            Username = uniqueKey + '.' + UserInfo.getOrganizationId() + '@example.com.rutacargo',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Mexico_City'
        );
    }

    /**
     * @description Unsaved Standard Platform Users (Salesforce Platform license),
     *              one per key. The org has 3 Salesforce Platform licenses, so a
     *              test must not insert more than 3 of them.
     * @param uniqueKeys short keys (letters and digits), one per user
     * @return the unsaved users, in the order of the keys
     */
    public static List<User> newPlatformUsers(List<String> uniqueKeys) {
        Id profileId = [SELECT Id FROM Profile WHERE Name = :PLATFORM_PROFILE_NAME WITH USER_MODE LIMIT 1].Id;
        List<User> users = new List<User>();
        for (String uniqueKey : uniqueKeys) {
            users.add(newUser(profileId, uniqueKey));
        }
        return users;
    }

    /**
     * @description The API-only integration user for a test (profile "Minimum
     *              Access - API Only Integrations", Salesforce Integration
     *              license). The org has 1 Salesforce Integration license and 1
     *              "Salesforce API Integration" permission set license, which the
     *              real EntregaYa integration user (req-004 T4) takes. So:
     *              - when an active user with that profile already holds the
     *                permission set license, that SAVED user is returned (Id set)
     *                and the test must not insert it nor assign the license again;
     *              - otherwise an UNSAVED new user is returned (Id null): the test
     *                inserts it and assigns the license
     *                (newApiIntegrationLicenseAssignment).
     *              Remaining risk: if the only Salesforce Integration license is
     *              held by a user without that profile or without the permission
     *              set license, the test cannot insert a new one.
     * @param uniqueKey a short key (letters and digits) that makes a new user unique in the test
     * @return the existing integration user, or an unsaved new one
     */
    public static User newOrExistingIntegrationUser(String uniqueKey) {
        List<User> existing = [
            SELECT Id, Username FROM User
            WHERE IsActive = true AND Profile.Name = :INTEGRATION_PROFILE_NAME
                AND Id IN (
                    SELECT AssigneeId FROM PermissionSetLicenseAssign
                    WHERE PermissionSetLicense.DeveloperName = :API_INTEGRATION_PSL
                )
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        if (reuseExistingIntegrationUserOnly) {
            throw new TestDataException('No active ' + INTEGRATION_PROFILE_NAME + ' user holds ' + API_INTEGRATION_PSL);
        }
        Id profileId = [SELECT Id FROM Profile WHERE Name = :INTEGRATION_PROFILE_NAME WITH USER_MODE LIMIT 1].Id;
        return newUser(profileId, uniqueKey);
    }

    /**
     * @description The SAVED guest user of the RutaCargo site (profile
     *              "RutaCargo Profile", 0 object permissions). The platform
     *              creates it with the site; tests never insert it, they run as
     *              it with System.runAs (req-001 AC-001.6).
     * @return the active site guest user
     */
    public static User siteGuestUser() {
        return [
            SELECT Id, Profile.Name, UserType FROM User
            WHERE Profile.Name = :SITE_GUEST_PROFILE_NAME AND IsActive = true AND UserType = 'Guest'
            WITH USER_MODE
            LIMIT 1
        ];
    }

    /**
     * @description Unsaved assignment of the "Salesforce API Integration"
     *              permission set license, which a Salesforce Integration user
     *              needs before a permission set can give it custom object access.
     * @param userId the integration user
     * @return the unsaved license assignment
     */
    public static PermissionSetLicenseAssign newApiIntegrationLicenseAssignment(Id userId) {
        Id licenseId = [
            SELECT Id FROM PermissionSetLicense WHERE DeveloperName = :API_INTEGRATION_PSL WITH USER_MODE LIMIT 1
        ].Id;
        return new PermissionSetLicenseAssign(AssigneeId = userId, PermissionSetLicenseId = licenseId);
    }

    /**
     * @description Unsaved permission set assignments of one permission set to
     *              each given user.
     */
    public static List<PermissionSetAssignment> newPermissionSetAssignments(Id permissionSetId, List<User> users) {
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (User member : users) {
            assignments.add(new PermissionSetAssignment(PermissionSetId = permissionSetId, AssigneeId = member.Id));
        }
        return assignments;
    }

    /**
     * @description Unsaved permission set that exists only inside one test (the
     *              test transaction rolls it back). Tests use it to give a user a
     *              narrower object permission than any deployed permission set.
     * @param name the API name of the permission set
     * @return the unsaved permission set
     */
    public static PermissionSet newTestPermissionSet(String name) {
        return new PermissionSet(Name = name, Label = name);
    }

    /**
     * @description Unsaved Read-only object permission (no Create, Edit, Delete,
     *              View All or Modify All) of one object in a permission set.
     * @param permissionSetId the permission set that receives the permission
     * @param sObjectType the API name of the object
     * @return the unsaved object permission
     */
    public static ObjectPermissions newReadOnlyObjectPermission(Id permissionSetId, String sObjectType) {
        return new ObjectPermissions(
            ParentId = permissionSetId,
            SobjectType = sObjectType,
            PermissionsRead = true,
            PermissionsCreate = false,
            PermissionsEdit = false,
            PermissionsDelete = false,
            PermissionsViewAllRecords = false,
            PermissionsModifyAllRecords = false
        );
    }

    /**
     * @description Unsaved manual shares of each shipment with one group. Tests
     *              use them to mirror a criteria-based sharing rule, which the
     *              platform does not evaluate in Apex tests (assumption A10).
     */
    public static List<Shipment__Share> newShipmentGroupShares(List<Shipment__c> shipments, Id groupId, String accessLevel) {
        List<Shipment__Share> shares = new List<Shipment__Share>();
        for (Shipment__c shipment : shipments) {
            shares.add(new Shipment__Share(
                ParentId = shipment.Id,
                UserOrGroupId = groupId,
                AccessLevel = accessLevel,
                RowCause = Schema.Shipment__Share.RowCause.Manual
            ));
        }
        return shares;
    }

    /**
     * @description Unsaved manual shares of each account with one group, with no
     *              access to the account's opportunities and cases (contacts
     *              follow the account: Controlled by Parent). Mirrors a
     *              criteria-based Account sharing rule in tests (assumption A10).
     */
    public static List<AccountShare> newAccountGroupShares(List<Account> accounts, Id groupId, String accessLevel) {
        List<AccountShare> shares = new List<AccountShare>();
        for (Account customer : accounts) {
            shares.add(new AccountShare(
                AccountId = customer.Id,
                UserOrGroupId = groupId,
                AccountAccessLevel = accessLevel,
                OpportunityAccessLevel = 'None',
                CaseAccessLevel = 'None'
            ));
        }
        return shares;
    }

    /**
     * @description Unsaved memberships of each given user in one public group.
     */
    public static List<GroupMember> newGroupMembers(Id groupId, List<User> users) {
        List<GroupMember> members = new List<GroupMember>();
        for (User member : users) {
            members.add(new GroupMember(GroupId = groupId, UserOrGroupId = member.Id));
        }
        return members;
    }

    // ─── Ready-made actors (saved): EntregaYa integration user, support agent ──

    // SECURITY-JUSTIFICATION: test fixture only. The running test admin writes
    // users, license and permission set assignments, group memberships and the
    // manual shares that mirror the criteria sharing rules (A10) in system mode,
    // because at API 67 DML defaults to user mode and the admin has no field
    // permissions on the RutaCargo fields. Scope: these TestDataFactory setup
    // helpers (updateAsSystem, deactivateUser and removePermissionSetAssignment
    // included; every change is rolled back with the test). Compensating control: every action under test runs inside
    // System.runAs as the actor, in user mode. (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Id of a deployed permission set.
     * @param name the API name of the permission set
     * @return its Id
     */
    public static Id permissionSetId(String name) {
        return [SELECT Id FROM PermissionSet WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    /**
     * @description Id of a deployed public group.
     * @param developerName the API name of the group
     * @return its Id
     */
    public static Id groupId(String developerName) {
        return [
            SELECT Id FROM Group WHERE DeveloperName = :developerName AND Type = 'Regular' WITH SYSTEM_MODE LIMIT 1
        ].Id;
    }

    /**
     * @description The SAVED EntregaYa integration user, ready to act: reuses the
     *              org's existing integration user (newOrExistingIntegrationUser,
     *              B8) or inserts a new one with the Salesforce API Integration
     *              permission set license, then makes sure it has the
     *              RutaCargo_EntregaYa_Integration permission set and is a member of
     *              the RutaCargo_EntregaYa_Integration group. Setup objects are
     *              written inside System.runAs (no mixed DML).
     * @param uniqueKey a short key (letters and digits) for a new user
     * @return the saved integration user
     */
    public static User insertEntregaYaIntegrationUser(String uniqueKey) {
        User integration = newOrExistingIntegrationUser(uniqueKey);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            if (integration.Id == null) {
                insertAsSystem(new List<User>{ integration });
                insertAsSystem(new List<PermissionSetLicenseAssign>{
                    newApiIntegrationLicenseAssignment(integration.Id) });
            }
            Id setId = permissionSetId(ENTREGAYA_PERMISSION_SET);
            if ([SELECT COUNT() FROM PermissionSetAssignment
                    WHERE AssigneeId = :integration.Id AND PermissionSetId = :setId WITH SYSTEM_MODE] == 0) {
                insertAsSystem(newPermissionSetAssignments(setId, new List<User>{ integration }));
            }
            Id integrationGroupId = groupId(ENTREGAYA_GROUP);
            if ([SELECT COUNT() FROM GroupMember
                    WHERE GroupId = :integrationGroupId AND UserOrGroupId = :integration.Id WITH SYSTEM_MODE] == 0) {
                insertAsSystem(newGroupMembers(integrationGroupId, new List<User>{ integration }));
            }
        }
        return integration;
    }

    /**
     * @description A SAVED support agent (Standard Platform User with the
     *              RutaCargo_Support_Agent permission set, member of the
     *              RutaCargo_Support_Agents group). Uses one of the org's 3
     *              Salesforce Platform licenses.
     * @param uniqueKey a short key (letters and digits) that makes the user unique
     * @return the saved agent
     */
    public static User insertSupportAgent(String uniqueKey) {
        User agent = newPlatformUsers(new List<String>{ uniqueKey })[0];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertAsSystem(new List<User>{ agent });
            insertAsSystem(newPermissionSetAssignments(permissionSetId(AGENT_PERMISSION_SET), new List<User>{ agent }));
            insertAsSystem(newGroupMembers(groupId(AGENT_GROUP), new List<User>{ agent }));
        }
        return agent;
    }

    /**
     * @description Inserts manual Edit shares of the shipments with a group,
     *              mirroring its criteria-based sharing rule (A10).
     * @param shipments saved shipments
     * @param groupDeveloperName the API name of the group
     */
    public static void insertShipmentGroupShares(List<Shipment__c> shipments, String groupDeveloperName) {
        insertAsSystem(newShipmentGroupShares(shipments, groupId(groupDeveloperName), RULE_ACCESS));
    }

    // ─── Recipient access (req-002-003) ───────────────────────────────────

    /**
     * @description A SAVED customer account, written in system mode (the test
     *              admin has no field permissions on the Account custom fields).
     * @param name the account name
     * @return the saved account
     */
    public static Account insertCustomerAccount(String name) {
        Account customer = newCustomerAccount(name);
        insertAsSystem(new List<Account>{ customer });
        return customer;
    }

    /**
     * @description Inserts the shipments in system mode and returns the clear
     *              access code of each one, captured from DeliveryAccessCode
     *              while the insert runs (the trigger issues the codes). The
     *              clear codes are removed from DeliveryAccessCode's memory
     *              before returning. Tests use the codes as a recipient would
     *              type them; they are never written to a field or a log.
     * @param shipments unsaved shipments
     * @return shipment Id to clear access code
     */
    public static Map<Id, String> insertShipmentsWithCodes(List<Shipment__c> shipments) {
        Map<Id, String> codes = new Map<Id, String>();
        DeliveryAccessCode.captureForTest = true;
        try {
            insertAsSystem(shipments);
            for (Shipment__c shipment : shipments) {
                codes.put(shipment.Id, DeliveryAccessCode.issuedCodesById.remove(shipment.Id));
            }
        } finally {
            DeliveryAccessCode.captureForTest = false;
            DeliveryAccessCode.pendingCodesByHash.clear();
            DeliveryAccessCode.issuedCodesById.clear();
        }
        return codes;
    }

    /**
     * @description Updates the records in system mode: tests set fields the
     *              trigger fixes on insert (Status__c, Reschedule_Count__c,
     *              Proof_Id__c) after inserting the shipment.
     * @param records saved records with the fields to change
     */
    public static void updateAsSystem(List<SObject> records) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Unsaved attempt guard of one shipment (keyed by its Id).
     * @param shipmentId the guarded shipment
     * @param failedAttempts the consecutive counted failures
     * @param lockedUntil the end of a lock, or null
     * @return the unsaved guard
     */
    public static Recipient_Access_Guard__c newRecipientAccessGuard(
        Id shipmentId, Integer failedAttempts, Datetime lockedUntil
    ) {
        return new Recipient_Access_Guard__c(
            Shipment__c = shipmentId,
            Shipment_Key__c = String.valueOf(shipmentId),
            Failed_Attempts__c = failedAttempts,
            Locked_Until__c = lockedUntil
        );
    }

    /**
     * @description Inserts attempt guards in system mode (no user holds any
     *              permission on Recipient_Access_Guard__c).
     * @param guards unsaved guards
     */
    public static void insertRecipientAccessGuards(List<Recipient_Access_Guard__c> guards) {
        insertAsSystem(guards);
    }

    // ─── Registered customers (req-005) ───────────────────────────────────

    public static final String CUSTOMER_PROFILE_NAME = 'RutaCargo Customer';
    public static final String CUSTOMER_PERMISSION_SET = 'RutaCargo_Customer';
    /** @description Email of the seeded customer Ana López (scripts/seed, req-005 T1). */
    public static final String SEEDED_CUSTOMER_EMAIL = 'ana.lopez@example.com';
    /** @description Email of the seeded customer Marta Ruiz (scripts/seed, req-005 T1). */
    public static final String SECOND_SEEDED_CUSTOMER_EMAIL = 'marta.ruiz@example.com';

    /**
     * @description The SAVED site user of a seeded customer (profile "RutaCargo
     *              Customer", created by scripts/setup/seed-customer-users.sh).
     *              Tests never insert portal users: the org has 3 free Customer
     *              Community seats (req-005 F7), so tests that need a real
     *              customer user query one of the two seeded users.
     * @param email the seeded customer's email
     * @return the seeded customer user
     */
    public static User seededCustomerUser(String email) {
        List<User> users = [
            SELECT Id, Username, Email, IsActive, ContactId FROM User
            WHERE Email = :email AND Profile.Name = :CUSTOMER_PROFILE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            throw new TestDataException('No ' + CUSTOMER_PROFILE_NAME + ' user has the seeded email; run scripts/setup/seed-customer-users.sh');
        }
        return users[0];
    }

    /**
     * @description A SAVED contact with the given email on the given account,
     *              written in system mode.
     * @param accountId the contact's account
     * @param email the contact's email
     * @return the saved contact
     */
    public static Contact insertCustomerContact(Id accountId, String email) {
        Contact person = new Contact(AccountId = accountId, FirstName = 'Test', LastName = 'Customer', Email = email);
        insertAsSystem(new List<Contact>{ person });
        return person;
    }

    /**
     * @description Deactivates a user inside the test (rolled back with it). Runs
     *              in its own System.runAs block, so it never mixes with DML on
     *              non-setup objects.
     * @param userId the user to deactivate
     */
    public static void deactivateUser(Id userId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            updateAsSystem(new List<User>{ new User(Id = userId, IsActive = false) });
        }
    }

    /**
     * @description Removes a user's assignment of one permission set inside the
     *              test (rolled back with it), so a test can prove that code
     *              assigns it again.
     * @param userId the assignee
     * @param permissionSetName the API name of the permission set
     */
    public static void removePermissionSetAssignment(Id userId, String permissionSetName) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Database.delete([
                SELECT Id FROM PermissionSetAssignment
                WHERE AssigneeId = :userId AND PermissionSet.Name = :permissionSetName
                WITH SYSTEM_MODE
            ], AccessLevel.SYSTEM_MODE);
        }
    }

    // ─── Customer shipment requests (req-006-007) ─────────────────────────

    /** @description Thursday 2026-11-19: "today" of the AC-006.3 examples (ShipmentRequestRules.todayOverride). */
    public static final Date REQUEST_TODAY = Date.newInstance(2026, 11, 19);
    /** @description Friday 2026-11-20: a valid pickup date (T+1) when today is REQUEST_TODAY. */
    public static final Date REQUEST_PICKUP_DATE = Date.newInstance(2026, 11, 20);

    /**
     * @description The account of a seeded customer user (User.AccountId).
     * @param email the seeded customer's email
     * @return the customer's account Id
     */
    public static Id seededCustomerAccountId(String email) {
        Id userId = seededCustomerUser(email).Id;
        return [SELECT AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE].AccountId;
    }

    /**
     * @description A complete, valid shipment request (every AC-006.1 field,
     *              the optional ones included): Standard, 2.5 kg, declared
     *              1,000.00, pickup REQUEST_PICKUP_DATE.
     * @return the request
     */
    public static ShipmentRequestController.ShipmentRequest newShipmentRequest() {
        ShipmentRequestController.ShipmentRequest request = new ShipmentRequestController.ShipmentRequest();
        request.pickupAddress = 'Av. Insurgentes Sur 1000, Col. Del Valle';
        request.pickupCity = 'Ciudad de Mexico';
        request.pickupPostalCode = '03100';
        request.pickupDate = REQUEST_PICKUP_DATE;
        request.recipientName = 'Laura Gomez';
        request.recipientAddress = 'Calle Hidalgo 45, Centro';
        request.recipientCity = 'Puebla';
        request.recipientPostalCode = '72000';
        request.recipientPhone = '+52 222 000 0000';
        request.recipientEmail = 'laura.gomez@example.com';
        request.serviceType = 'Standard';
        request.weightKg = 2.50;
        request.packageDescription = 'Office supplies';
        request.declaredValue = 1000.00;
        request.customerReference = 'PO-2026-001';
        request.deliveryInstructions = 'Ring the bell twice';
        return request;
    }

    /**
     * @description Unsaved shipments as a customer would create them directly
     *              (UI API or DML): the AC-006.1 fields only, no account, valid
     *              when today is REQUEST_TODAY (Standard, 2.5 kg, declared
     *              1,000.00, pickup REQUEST_PICKUP_DATE).
     * @param count how many
     * @return the unsaved shipments
     */
    public static List<Shipment__c> newCustomerShipments(Integer count) {
        List<Shipment__c> shipments = newShipments(null, count);
        for (Shipment__c shipment : shipments) {
            shipment.Pickup_Date__c = REQUEST_PICKUP_DATE;
            shipment.Weight_Kg__c = 2.50;
            shipment.Declared_Value__c = 1000.00;
        }
        return shipments;
    }

    // ─── EntregaYa status requests ────────────────────────────────────────

    /**
     * @description An EntregaYa status change with the given fields (the five
     *              fields of the decided contract, so five parameters).
     * @param trackingNumber the tracking number
     * @param status the status
     * @param location the location
     * @param timestamp the ISO-8601 timestamp
     * @param proofId the proof of delivery id, or null
     * @return the request
     */
    public static EntregaYaStatusRequest newStatusRequest(
        String trackingNumber, String status, String location, String timestamp, String proofId
    ) {
        EntregaYaStatusRequest request = new EntregaYaStatusRequest();
        request.trackingNumber = trackingNumber;
        request.status = status;
        request.location = location;
        request.timestamp = timestamp;
        request.proofId = proofId;
        return request;
    }

    /**
     * @description The JSON fields of an EntregaYa status POST body (the five keys
     *              of the decided contract; a null proofId stays as JSON null, as
     *              EntregaYa sends it). Tests serialize it with JSON.serialize and
     *              may remove or retype keys first.
     * @param trackingNumber the tracking number
     * @param status the status
     * @param location the location
     * @param timestamp the ISO-8601 timestamp
     * @param proofId the proof of delivery id, or null
     * @return the body fields, in contract order
     */
    public static Map<String, Object> newStatusRequestFields(
        String trackingNumber, String status, String location, String timestamp, String proofId
    ) {
        return new Map<String, Object>{
            'trackingNumber' => trackingNumber,
            'status' => status,
            'location' => location,
            'timestamp' => timestamp,
            'proofId' => proofId
        };
    }
}
