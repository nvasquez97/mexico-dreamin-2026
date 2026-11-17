/** REQ-005 — sign-up and login. Site.createExternalUser / Site.login only run inside a site, so the
 *  tests cover validation, duplicate detection, account creation and the guarded paths. */
@IsTest
private class CustomerAuthControllerTest {
  // Users are not isolated in tests: use an email no real site user can have.
  private static final String EMAIL =
    'rosa.' +
    Crypto.getRandomInteger() +
    '@estrella-test.example';

  private static CustomerAuthController.RegistrationRequest request() {
    CustomerAuthController.RegistrationRequest r = new CustomerAuthController.RegistrationRequest();
    r.customerType = 'Business';
    r.accountName = 'Papelería La Estrella S.A. de C.V.';
    r.firstName = 'Rosa';
    r.lastName = 'Méndez';
    r.email = EMAIL.toUpperCase();
    r.phone = '55 5555 0101';
    r.password = 'Envios2026seguro';
    r.startUrl = '/rutacargo/request-shipment';
    return r;
  }

  @IsTest
  static void ac005_1_formRequiresAllFields() {
    CustomerAuthController.AuthResult r = CustomerAuthController.register(
      new CustomerAuthController.RegistrationRequest()
    );
    Assert.isFalse(r.success);
    for (
      String expected : new List<String>{
        'individual or a business',
        'Name or legal name',
        'First name',
        'Last name',
        'valid email',
        'phone',
        'password'
      }
    ) {
      Assert.isTrue(
        r.message.contains(expected),
        'Missing message: ' + expected + ' in ' + r.message
      );
    }
    Assert.isFalse(CustomerAuthController.register(null).success);
  }

  @IsTest
  static void ac005_2_signUpCreatesTheCustomerAccount() {
    User owner = new User(Id = UserInfo.getUserId());
    insert new RutaCargo_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Account_Owner_Id__c = owner.Id
    );
    CustomerAuthController.AuthResult r = CustomerAuthController.register(
      request()
    );
    Assert.isTrue(r.success, '' + r.message);
    Account a = [
      SELECT Name, Customer_Type__c, Phone, OwnerId
      FROM Account
      WHERE Name = 'Papelería La Estrella S.A. de C.V.'
    ];
    Assert.areEqual('Business', a.Customer_Type__c);
    Assert.areEqual('55 5555 0101', a.Phone);
    Assert.areEqual(owner.Id, a.OwnerId);
  }

  @IsTest
  static void ac005_3_emailAlreadyRegisteredOffersLogin() {
    Account a = RutaCargoTestFactory.customer('Existing');
    insert new Contact(LastName = 'Méndez', Email = EMAIL, AccountId = a.Id);
    CustomerAuthController.AuthResult r = CustomerAuthController.register(
      request()
    );
    Assert.isFalse(r.success);
    Assert.isTrue(r.duplicate);
    Assert.areEqual(CustomerAuthController.MSG_DUPLICATE, r.message);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Account],
      'No second account is created'
    );
  }

  @IsTest
  static void ac005_3_emailOfAnExistingSiteUserIsDuplicate() {
    User siteUser = RutaCargoTestFactory.customerUser(
      'Acme',
      'ana@acme.example'
    );
    CustomerAuthController.RegistrationRequest r = request();
    r.email = 'ANA@acme.example';
    Assert.isTrue(CustomerAuthController.register(r).duplicate);
  }

  @IsTest
  static void ac005_4_passwordNeedsTenCharactersWithLettersAndNumbers() {
    Assert.isTrue(CustomerAuthController.isValidPassword('abcdefghi1'));
    Assert.isFalse(
      CustomerAuthController.isValidPassword('abcdefgh1'),
      'only 9 characters'
    );
    Assert.isFalse(
      CustomerAuthController.isValidPassword('abcdefghijk'),
      'no numbers'
    );
    Assert.isFalse(
      CustomerAuthController.isValidPassword('12345678901'),
      'no letters'
    );
    Assert.isFalse(CustomerAuthController.isValidPassword(null));
    CustomerAuthController.RegistrationRequest weak = request();
    weak.password = 'short1';
    CustomerAuthController.AuthResult r = CustomerAuthController.register(weak);
    Assert.isFalse(r.success);
    Assert.isTrue(r.message.contains('at least 10 characters'));
  }

  @IsTest
  static void ac005_5_loginRejectsUnknownEmailsAndEmptyPasswords() {
    CustomerAuthController.AuthResult unknown = CustomerAuthController.login(
      'nobody@example.com',
      'whatever123',
      null
    );
    Assert.isFalse(unknown.success);
    Assert.areEqual(CustomerAuthController.MSG_LOGIN_FAILED, unknown.message);
    RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    Assert.isFalse(
      CustomerAuthController.login('ana@acme.example', '', null).success
    );
    Assert.isFalse(CustomerAuthController.login(null, null, null).success);
    // Outside a site Site.login cannot log anybody in: the generic message is shown.
    Assert.areEqual(
      CustomerAuthController.MSG_LOGIN_FAILED,
      CustomerAuthController.login(
          ' Ana@Acme.example ',
          'Password123',
          '/rutacargo'
        )
        .message
    );
  }

  @IsTest
  static void ac005_5_loginOnlyRedirectsInsideTheSite() {
    Assert.areEqual(
      '/rutacargo/my-shipments',
      CustomerAuthController.safeStartUrl('/rutacargo/my-shipments')
    );
    Assert.isNull(CustomerAuthController.safeStartUrl('https://evil.example'));
    Assert.isNull(CustomerAuthController.safeStartUrl('//evil.example'));
    Assert.isNull(CustomerAuthController.safeStartUrl('/\\evil.example'));
    Assert.isNull(CustomerAuthController.safeStartUrl(''));
  }

  @IsTest
  static void ac005_6_passwordResetAnswersTheSameForAnyEmail() {
    RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    CustomerAuthController.AuthResult known = CustomerAuthController.forgotPassword(
      'ana@acme.example'
    );
    CustomerAuthController.AuthResult unknown = CustomerAuthController.forgotPassword(
      'nobody@example.com'
    );
    Assert.isTrue(known.success);
    Assert.areEqual(
      known.message,
      unknown.message,
      'Does not reveal which emails are registered'
    );
  }

  @IsTest
  static void usernameIsTheEmailWithAnOrgSuffix() {
    String username = CustomerAuthController.usernameFor(' Ana@Acme.example ');
    Assert.isTrue(username.startsWith('ana@acme.example.rc'));
    Assert.isTrue(
      username.endsWith(
        String.valueOf(UserInfo.getOrganizationId()).left(15).toLowerCase()
      )
    );
  }

  @IsTest
  static void contactPhoneIsCopiedAfterSignUp() {
    User siteUser = RutaCargoTestFactory.customerUser(
      'Acme',
      'ana@acme.example'
    );
    Test.startTest();
    CustomerAuthController.syncContactPhone(siteUser.Id, '55 1234 5678');
    Test.stopTest();
    Assert.areEqual(
      '55 1234 5678',
      [SELECT Phone FROM Contact WHERE Id = :siteUser.ContactId].Phone
    );
  }
}
