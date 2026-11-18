/**
 * @description Guest-callable customer sign-up of the RutaCargo site
 *              (odd/tasks/req-005-customer-signup.md S2, AC-005.1 to AC-005.4).
 *              It receives individual fields only, validates every one on the
 *              server, normalizes the email and hands the validated values to
 *              CustomerRegistration, which checks that the email is not
 *              registered and creates the Account, the Contact and the user.
 *              Messages are generic and never echo the input.
 */
public with sharing class CustomerSignUpController {

    public static final String CODE_CREATED = 'CREATED';
    public static final String CODE_INVALID = 'INVALID';
    public static final String CODE_EMAIL_REGISTERED = 'EMAIL_REGISTERED';
    public static final String CODE_FAILED = 'FAILED';

    public static final String MESSAGE_CREATED = 'Your account is ready. Log in with your email and password.';
    public static final String MESSAGE_CUSTOMER_TYPE = 'Choose Individual or Business.';
    public static final String MESSAGE_ACCOUNT_NAME = 'Enter the name or legal name (up to 255 characters).';
    public static final String MESSAGE_FIRST_NAME = 'Enter the first name (up to 40 characters).';
    public static final String MESSAGE_LAST_NAME = 'Enter the last name (up to 80 characters).';
    public static final String MESSAGE_EMAIL = 'Enter a valid email address (up to 61 characters).';
    public static final String MESSAGE_PHONE = 'Enter a valid phone number (digits, spaces, +, -, parentheses; up to 40 characters).';
    public static final String MESSAGE_PASS_RULES = 'The password needs at least 10 characters, with letters and numbers.';
    public static final String MESSAGE_CONFIRMATION = 'The password and its confirmation do not match.';
    public static final String MESSAGE_PASS_POLICY = 'This password does not meet the password policy. Choose another one.';
    public static final String MESSAGE_EMAIL_REGISTERED = 'This email is already registered. Log in instead.';
    public static final String MESSAGE_FAILED = 'We could not create your account. Please try again later.';

    private static final Set<String> CUSTOMER_TYPES = new Set<String>{ 'Individual', 'Business' };
    private static final Integer MAX_ACCOUNT_NAME = 255;
    private static final Integer MAX_FIRST_NAME = 40;
    private static final Integer MAX_LAST_NAME = 80;
    // The username adds "." + the 18-character org Id (19) and holds 80.
    private static final Integer MAX_EMAIL = 61;
    private static final Integer MAX_PHONE = 40;
    private static final Integer MIN_PHONE_DIGITS = 7;
    private static final Integer MIN_PASSWORD = 10;
    private static final Integer MAX_PASSWORD = 128;
    private static final Pattern EMAIL_FORMAT = Pattern.compile('[a-z0-9._%+\\-]+@[a-z0-9\\-]+(\\.[a-z0-9\\-]+)*\\.[a-z]{2,}');
    private static final Pattern PHONE_CHARACTERS = Pattern.compile('[0-9+() .\\-]+');
    private static final Pattern HAS_LETTER = Pattern.compile('.*[A-Za-z].*');
    private static final Pattern HAS_DIGIT = Pattern.compile('.*[0-9].*');

    /** @description The answer of a sign-up. */
    public inherited sharing class SignUpResult {
        /** @description True when the customer was created. */
        @AuraEnabled public Boolean success;
        /** @description CREATED, INVALID, EMAIL_REGISTERED or FAILED. */
        @AuraEnabled public String code;
        /** @description The rejected field (form field name), or null. */
        @AuraEnabled public String field;
        /** @description A generic message for the visitor. */
        @AuraEnabled public String message;
    }

    /**
     * @description Signs up a customer (an Account with its Contact and a site
     *              user of the profile "RutaCargo Customer").
     * @param customerType Individual or Business
     * @param accountName the person's name or the legal name
     * @param firstName the contact's first name
     * @param lastName the contact's last name
     * @param email the email (trimmed and lower-cased on the server)
     * @param phone the phone
     * @param password the password
     * @param confirmPassword the password again
     * @return the result: created, a field error, email registered, or a generic failure
     */
    @AuraEnabled
    public static SignUpResult signUp(
        String customerType, String accountName, String firstName, String lastName,
        String email, String phone, String password, String confirmPassword
    ) {
        String normalizedEmail = CustomerRegistration.normalizeEmail(email);
        SignUpResult invalid = firstInvalidField(
            customerType, accountName, firstName, lastName, normalizedEmail, phone, password, confirmPassword
        );
        if (invalid != null) {
            return invalid;
        }
        CustomerRegistration.Applicant applicant = new CustomerRegistration.Applicant();
        applicant.customerType = customerType;
        applicant.accountName = accountName.trim();
        applicant.firstName = firstName.trim();
        applicant.lastName = lastName.trim();
        applicant.email = normalizedEmail;
        applicant.phone = phone.trim();
        return toResult(CustomerRegistration.register(applicant, password));
    }

    private static SignUpResult firstInvalidField(
        String customerType, String accountName, String firstName, String lastName,
        String normalizedEmail, String phone, String password, String confirmPassword
    ) {
        if (!CUSTOMER_TYPES.contains(customerType)) {
            return invalid('customerType', MESSAGE_CUSTOMER_TYPE);
        }
        if (!isFilled(accountName, MAX_ACCOUNT_NAME)) {
            return invalid('accountName', MESSAGE_ACCOUNT_NAME);
        }
        if (!isFilled(firstName, MAX_FIRST_NAME)) {
            return invalid('firstName', MESSAGE_FIRST_NAME);
        }
        if (!isFilled(lastName, MAX_LAST_NAME)) {
            return invalid('lastName', MESSAGE_LAST_NAME);
        }
        if (!isValidEmail(normalizedEmail)) {
            return invalid('email', MESSAGE_EMAIL);
        }
        if (!isValidPhone(phone)) {
            return invalid('phone', MESSAGE_PHONE);
        }
        if (!isValidPassword(password)) {
            return invalid('password', MESSAGE_PASS_RULES);
        }
        // equals, not ==: Apex == compares strings without case.
        if (!password.equals(confirmPassword)) {
            return invalid('confirmPassword', MESSAGE_CONFIRMATION);
        }
        return null;
    }

    private static Boolean isFilled(String value, Integer maxLength) {
        return String.isNotBlank(value) && value.trim().length() <= maxLength;
    }

    private static Boolean isValidEmail(String normalizedEmail) {
        return String.isNotBlank(normalizedEmail)
            && normalizedEmail.length() <= MAX_EMAIL
            && EMAIL_FORMAT.matcher(normalizedEmail).matches();
    }

    private static Boolean isValidPhone(String phone) {
        if (!isFilled(phone, MAX_PHONE) || !PHONE_CHARACTERS.matcher(phone.trim()).matches()) {
            return false;
        }
        return phone.replaceAll('[^0-9]', '').length() >= MIN_PHONE_DIGITS;
    }

    private static Boolean isValidPassword(String password) {
        return password != null
            && password.length() >= MIN_PASSWORD
            && password.length() <= MAX_PASSWORD
            && HAS_LETTER.matcher(password).matches()
            && HAS_DIGIT.matcher(password).matches();
    }

    private static SignUpResult toResult(CustomerRegistration.Outcome outcome) {
        switch on outcome {
            when CREATED {
                return result(true, CODE_CREATED, null, MESSAGE_CREATED);
            }
            when REGISTERED {
                return result(false, CODE_EMAIL_REGISTERED, 'email', MESSAGE_EMAIL_REGISTERED);
            }
            when INVALID_PASSWORD {
                return invalid('password', MESSAGE_PASS_POLICY);
            }
            when else {
                return result(false, CODE_FAILED, null, MESSAGE_FAILED);
            }
        }
    }

    private static SignUpResult invalid(String field, String message) {
        return result(false, CODE_INVALID, field, message);
    }

    private static SignUpResult result(Boolean success, String code, String field, String message) {
        SignUpResult answer = new SignUpResult();
        answer.success = success;
        answer.code = code;
        answer.field = field;
        answer.message = message;
        return answer;
    }
}
