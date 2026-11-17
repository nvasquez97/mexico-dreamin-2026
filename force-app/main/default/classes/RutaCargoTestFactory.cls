/**
 * Test data for the RutaCargo test classes. "Today" is pinned to Wednesday 2026-11-18 in
 * Mexico City (18:00 UTC = 12:00 CDMX) so date rules are deterministic.
 * Inserts use SYSTEM_MODE: with API 67 DML runs in user mode by default, and test users
 * (e.g. the generated account owner) have no field permissions on the RutaCargo fields.
 */
@IsTest
public class RutaCargoTestFactory {
  public static final Datetime NOW = Datetime.newInstanceGmt(
    2026,
    11,
    18,
    18,
    0,
    0
  );
  public static final Date TODAY = Date.newInstance(2026, 11, 18); // Wednesday

  public static void pinToday() {
    RutaCargoDates.nowOverride = NOW;
  }

  public static Account customer(String name) {
    Account account = new Account(
      Name = name,
      Customer_Type__c = 'Business',
      Credit_Limit__c = 1000,
      Credit_Risk__c = 'Low'
    );
    Database.insert(account, AccessLevel.SYSTEM_MODE);
    return account;
  }

  public static Shipment__c shipment(Id accountId, String status) {
    return new Shipment__c(
      Account__c = accountId,
      Status__c = status,
      Service_Type__c = 'Standard',
      Customer_Reference__c = null,
      Pickup_Address__c = 'Calle Fresno 214',
      Origin_City__c = 'Ciudad de México, CDMX',
      Pickup_Postal_Code__c = '06400',
      Pickup_Date__c = TODAY.addDays(-2),
      Destination_City__c = 'Monterrey, N.L.',
      Destination_Postal_Code__c = '64000',
      Recipient_Name__c = 'Lucía Hernández',
      Recipient_Address__c = 'Av. Juárez 120, Col. Centro',
      Recipient_Phone__c = '81 5123 4567',
      Recipient_Email__c = 'lucia@correo.example',
      Delivery_Instructions__c = 'Tocar el timbre',
      Package_Description__c = 'Café de grano',
      Weight_Kg__c = 2,
      Declared_Value__c = 1000,
      Price__c = 171,
      Carrier_Cost__c = 100,
      Internal_Notes__c = 'Internal only',
      Estimated_Delivery__c = TODAY.addDays(2),
      Last_Location__c = 'Querétaro, Qro.',
      Last_Update__c = NOW.addHours(-3)
    );
  }

  public static Shipment__c insertShipment(Id accountId, String status) {
    Shipment__c s = shipment(accountId, status);
    Database.insert(s, AccessLevel.SYSTEM_MODE);
    return [SELECT Id, Name FROM Shipment__c WHERE Id = :s.Id];
  }

  public static String trackingNumber(Id shipmentId) {
    return [SELECT Name FROM Shipment__c WHERE Id = :shipmentId].Name;
  }

  /** A site user (RutaCargo Customer profile) for a new customer account owned by a user with a role. */
  public static User customerUser(String accountName, String email) {
    User owner;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      UserRole role = new UserRole(Name = 'RC Test Owner Role ' + accountName);
      insert role;
      Profile admin = [
        SELECT Id
        FROM Profile
        WHERE PermissionsModifyAllData = TRUE AND UserType = 'Standard'
        LIMIT 1
      ];
      owner = new User(
        Username = 'owner.' +
          Crypto.getRandomInteger() +
          '@rutacargo-test.example',
        Email = 'owner@rutacargo-test.example',
        LastName = 'Owner',
        Alias = 'rcowner',
        ProfileId = admin.Id,
        UserRoleId = role.Id,
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'es_MX',
        TimeZoneSidKey = 'America/Mexico_City',
        EmailEncodingKey = 'UTF-8'
      );
      insert owner;
    }
    Contact contact;
    System.runAs(owner) {
      Account account = new Account(
        Name = accountName,
        Customer_Type__c = 'Business',
        OwnerId = owner.Id
      );
      Database.insert(account, AccessLevel.SYSTEM_MODE);
      contact = new Contact(
        LastName = 'Customer',
        FirstName = 'Test',
        Email = email,
        AccountId = account.Id
      );
      Database.insert(contact, AccessLevel.SYSTEM_MODE);
    }
    User siteUser;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      siteUser = new User(
        Username = CustomerAuthController.usernameFor(email),
        Email = email,
        LastName = 'Customer',
        FirstName = 'Test',
        Alias = 'rccust',
        ContactId = contact.Id,
        ProfileId = [
          SELECT Id
          FROM Profile
          WHERE Name = 'RutaCargo Customer'
          LIMIT 1
        ]
        .Id,
        LanguageLocaleKey = 'en_US',
        LocaleSidKey = 'es_MX',
        TimeZoneSidKey = 'America/Mexico_City',
        EmailEncodingKey = 'UTF-8'
      );
      insert siteUser;
    }
    return [
      SELECT Id, AccountId, ContactId, Email, Username
      FROM User
      WHERE Id = :siteUser.Id
    ];
  }
}
