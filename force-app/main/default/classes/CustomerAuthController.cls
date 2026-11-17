/**
 * REQ-005 — customer sign-up, login and password reset from the RutaCargo site (guest user).
 *
 * WITHOUT SHARING: the guest user must check whether an email is already registered and
 * create the customer's Account; it never returns record data to the browser.
 * Customers log in with their email. Salesforce usernames are global across all orgs, so the
 * username is the email plus an org-specific suffix and is resolved on the server.
 */
public without sharing class CustomerAuthController {
  public static final String MSG_DUPLICATE = 'This email is already registered. Log in or reset your password.';
  public static final String MSG_LOGIN_FAILED = 'Your email or password is incorrect.';
  private static final Pattern EMAIL_PATTERN = Pattern.compile(
    '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$'
  );
  private static final Pattern PHONE_PATTERN = Pattern.compile(
    '^\\+?[0-9 ()\\-]{10,20}$'
  );
  private static final Pattern HAS_LETTER = Pattern.compile('.*[A-Za-z].*');
  private static final Pattern HAS_DIGIT = Pattern.compile('.*[0-9].*');

  public class RegistrationRequest {
    @AuraEnabled
    public String customerType { get; set; }
    @AuraEnabled
    public String accountName { get; set; }
    @AuraEnabled
    public String firstName { get; set; }
    @AuraEnabled
    public String lastName { get; set; }
    @AuraEnabled
    public String email { get; set; }
    @AuraEnabled
    public String phone { get; set; }
    @AuraEnabled
    public String password { get; set; }
    @AuraEnabled
    public String startUrl { get; set; }
  }

  public class AuthResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public Boolean duplicate;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String redirectUrl;
  }

  public class RegistrationException extends Exception {
  }

  // ------------------------------------------------------------------ sign-up

  @AuraEnabled
  public static AuthResult register(RegistrationRequest request) {
    AuthResult result = new AuthResult();
    result.success = false;
    result.duplicate = false;
    try {
      validate(request);
    } catch (RegistrationException e) {
      result.message = e.getMessage();
      return result;
    }
    String email = request.email.trim().toLowerCase();
    // AC-005.3
    if (isEmailRegistered(email)) {
      result.duplicate = true;
      result.message = MSG_DUPLICATE;
      return result;
    }

    Savepoint sp = Database.setSavepoint();
    try {
      // AC-005.2 — the customer is an Account; the contact is created with the site user.
      Account account = new Account(
        Name = request.accountName.trim(),
        Customer_Type__c = request.customerType,
        Phone = request.phone.trim()
      );
      Id ownerId = accountOwnerId();
      if (ownerId != null) {
        account.OwnerId = ownerId;
      }
      Database.insert(account, AccessLevel.SYSTEM_MODE);

      User siteUser = buildUser(request, email);
      Id userId = createExternalUser(siteUser, account.Id, request.password);
      if (userId != null) {
        syncContactPhone(userId, request.phone.trim());
      }
      result.success = true;
      result.redirectUrl = Test.isRunningTest()
        ? null
        : loginUrl(siteUser.Username, request.password, request.startUrl);
      return result;
    } catch (Site.ExternalUserCreateException e) {
      Database.rollback(sp);
      result.message = String.join(e.getDisplayMessages(), ' ');
      return result;
    } catch (Exception e) {
      Database.rollback(sp);
      System.debug(
        LoggingLevel.ERROR,
        'Registration failed: ' + e.getMessage()
      );
      result.message = 'We could not create your account. Please try again.';
      return result;
    }
  }

  // ------------------------------------------------------------------ login (AC-005.5)

  @AuraEnabled
  public static AuthResult login(
    String email,
    String password,
    String startUrl
  ) {
    AuthResult result = new AuthResult();
    result.success = false;
    result.duplicate = false;
    String username = String.isBlank(email)
      ? null
      : findUsername(email.trim().toLowerCase());
    if (username == null || String.isBlank(password)) {
      result.message = MSG_LOGIN_FAILED;
      return result;
    }
    try {
      String url = loginUrl(username, password, startUrl);
      if (url == null) {
        result.message = MSG_LOGIN_FAILED;
        return result;
      }
      result.success = true;
      result.redirectUrl = url;
    } catch (Exception e) {
      result.message = MSG_LOGIN_FAILED;
    }
    return result;
  }

  // ------------------------------------------------------------------ password reset (AC-005.6)

  /** Always answers the same way so the form cannot be used to discover registered emails. */
  @AuraEnabled
  public static AuthResult forgotPassword(String email) {
    AuthResult result = new AuthResult();
    result.success = true;
    result.duplicate = false;
    result.message = 'If the email is registered, you will receive a link to reset your password.';
    String username = String.isBlank(email)
      ? null
      : findUsername(email.trim().toLowerCase());
    if (username != null && !Test.isRunningTest()) {
      Site.forgotPassword(username);
    }
    return result;
  }

  // ------------------------------------------------------------------ helpers

  public static void validate(RegistrationRequest request) {
    List<String> errors = new List<String>();
    if (request == null) {
      throw new RegistrationException('The sign-up form is empty.');
    }
    if (
      request.customerType != ShipmentConstants.CUSTOMER_INDIVIDUAL &&
      request.customerType != ShipmentConstants.CUSTOMER_BUSINESS
    ) {
      errors.add('Choose whether you are an individual or a business.');
    }
    if (
      String.isBlank(request.accountName) ||
      request.accountName.trim().length() > 255
    ) {
      errors.add('Name or legal name is required.');
    }
    if (
      String.isBlank(request.firstName) ||
      request.firstName.trim().length() > 40
    ) {
      errors.add('First name is required.');
    }
    if (
      String.isBlank(request.lastName) || request.lastName.trim().length() > 80
    ) {
      errors.add('Last name is required.');
    }
    if (
      String.isBlank(request.email) ||
      !EMAIL_PATTERN.matcher(request.email.trim()).matches() ||
      request.email.trim().length() > 60
    ) {
      errors.add('Enter a valid email.');
    }
    if (
      String.isBlank(request.phone) ||
      !PHONE_PATTERN.matcher(request.phone.trim()).matches()
    ) {
      errors.add('Enter a phone number with at least 10 digits.');
    }
    if (!isValidPassword(request.password)) {
      errors.add(
        'The password must have at least 10 characters, with letters and numbers.'
      );
    }
    if (!errors.isEmpty()) {
      throw new RegistrationException(String.join(errors, ' '));
    }
  }

  /** AC-005.4 */
  public static Boolean isValidPassword(String password) {
    return password != null &&
      password.length() >= ShipmentConstants.MIN_PASSWORD_LENGTH &&
      HAS_LETTER.matcher(password).matches() &&
      HAS_DIGIT.matcher(password).matches();
  }

  public static String usernameFor(String email) {
    return email.trim().toLowerCase() +
      '.rc' +
      String.valueOf(UserInfo.getOrganizationId()).left(15).toLowerCase();
  }

  @TestVisible
  private static Boolean isEmailRegistered(String email) {
    Integer users = [
      SELECT COUNT()
      FROM User
      WHERE
        (Email = :email
        OR Username = :usernameFor(email))
        AND ContactId != NULL
      WITH SYSTEM_MODE
    ];
    if (users > 0) {
      return true;
    }
    return [
        SELECT COUNT()
        FROM Contact
        WHERE Email = :email AND Account.Customer_Type__c != NULL
        WITH SYSTEM_MODE
      ] > 0;
  }

  private static String findUsername(String email) {
    List<User> users = [
      SELECT Username
      FROM User
      WHERE Email = :email AND ContactId != NULL AND IsActive = TRUE
      WITH SYSTEM_MODE
      ORDER BY CreatedDate
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0].Username;
  }

  private static User buildUser(RegistrationRequest request, String email) {
    String nickname = (request.firstName.trim().left(20) +
      '.' +
      String.valueOf(Crypto.getRandomInteger()).remove('-'))
      .left(40);
    String alias = (request.firstName.trim().left(1) +
      request.lastName.trim().left(4))
      .toLowerCase();
    return new User(
      Username = usernameFor(email),
      Email = email,
      FirstName = request.firstName.trim(),
      LastName = request.lastName.trim(),
      Phone = request.phone.trim(),
      CommunityNickname = nickname,
      Alias = alias.left(8),
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'es_MX',
      TimeZoneSidKey = RutaCargoDates.MEXICO_CITY_TZ,
      EmailEncodingKey = 'UTF-8'
    );
  }

  private static Id accountOwnerId() {
    RutaCargo_Settings__c settings = RutaCargo_Settings__c.getOrgDefaults();
    return settings == null || String.isBlank(settings.Account_Owner_Id__c)
      ? null
      : (Id) settings.Account_Owner_Id__c;
  }

  @TestVisible
  private static Id createExternalUser(
    User siteUser,
    Id accountId,
    String password
  ) {
    if (Test.isRunningTest()) {
      return null; // Site.createExternalUser only works in a site context.
    }
    return Site.createExternalUser(siteUser, accountId, password, false);
  }

  private static String loginUrl(
    String username,
    String password,
    String startUrl
  ) {
    PageReference page = Site.login(username, password, safeStartUrl(startUrl));
    return page == null ? null : page.getUrl();
  }

  /** Only site-relative paths are accepted, so the login cannot redirect to another domain. */
  @TestVisible
  private static String safeStartUrl(String startUrl) {
    if (String.isBlank(startUrl)) {
      return null;
    }
    String value = startUrl.trim();
    if (
      !value.startsWith('/') ||
      value.startsWith('//') ||
      value.contains('\\') ||
      value.containsIgnoreCase('javascript:')
    ) {
      return null;
    }
    return value;
  }

  /** The contact is created by the platform with the user; copy the phone afterwards (setup/non-setup DML). */
  @future
  public static void syncContactPhone(Id userId, String phone) {
    List<User> users = [
      SELECT ContactId
      FROM User
      WHERE Id = :userId AND ContactId != NULL
      WITH SYSTEM_MODE
    ];
    if (!users.isEmpty()) {
      Database.update(
        new Contact(Id = users[0].ContactId, Phone = phone),
        AccessLevel.SYSTEM_MODE
      );
    }
  }
}
