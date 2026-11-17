# Vulnerable → fixed patterns

## SOQL injection (P8)

```apex
// VULNERABLE: name and sortField flow straight into the query string
@AuraEnabled
public static List<Account> search(String name, String sortField) {
    String q = 'SELECT Id, Name FROM Account WHERE Name LIKE \'%' + name + '%\' ORDER BY ' + sortField;
    return Database.query(q);
}
// name = "x%' OR Name != '" returns every account; sortField can inject subqueries/limits.
```

```apex
// FIXED: values are bind variables, identifiers come from an allowlist, user mode enforced
private static final Set<String> SORTABLE = new Set<String>{ 'Name', 'CreatedDate' };

@AuraEnabled(cacheable=true)
public static List<Account> search(String name, String sortField) {
    if (!SORTABLE.contains(sortField)) {
        throw new AuraHandledException('Invalid sort field');
    }
    return Database.queryWithBinds(
        'SELECT Id, Name FROM Account WHERE Name LIKE :name ORDER BY ' + sortField,
        new Map<String, Object>{ 'name' => '%' + name + '%' },
        AccessLevel.USER_MODE
    );
}
```
(Concatenating an allowlisted identifier is acceptable — say so when dismissing the scanner hit.)

## Sharing and system mode (P10, P11)

```apex
// VULNERABLE: entry point bypasses sharing and CRUD/FLS
public without sharing class CaseController {
    @AuraEnabled
    public static List<Case> myCases() {
        return [SELECT Id, Subject, Description FROM Case];
    }
}
```

```apex
// FIXED: entry point enforces sharing + user mode; elevation is isolated, gated and justified
public with sharing class CaseController {
    @AuraEnabled(cacheable=true)
    public static List<Case> myCases() {
        return [SELECT Id, Subject FROM Case WITH USER_MODE];
    }

    @AuraEnabled(cacheable=true)
    public static Integer openCaseCount() {
        return CaseMetricsElevated.countOpen();
    }
}

// SECURITY-JUSTIFICATION: dashboard tile shows org-wide open case count (no record data);
// gated by View_Global_Case_Metrics custom permission. (Security team, 2026-11-15)
public without sharing class CaseMetricsElevated {
    public static Integer countOpen() {
        if (!FeatureManagement.checkPermission('View_Global_Case_Metrics')) {
            throw new AuraHandledException('Insufficient access');
        }
        return [SELECT COUNT() FROM Case WHERE IsClosed = false WITH SYSTEM_MODE];
    }
}
```

DML in user mode:
```apex
insert as user contacts;
Database.update(records, AccessLevel.USER_MODE);

SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, records);
insert as user decision.getRecords();
```

## IDOR (X5)

```apex
// VULNERABLE (on API < 67 or without sharing): any user can read any invoice by Id
@AuraEnabled
public static Invoice__c getInvoice(Id invoiceId) {
    return [SELECT Id, Amount__c, Customer__c FROM Invoice__c WHERE Id = :invoiceId];
}

// FIXED: sharing + user mode; a record the user cannot see returns no rows
@AuraEnabled(cacheable=true)
public static Invoice__c getInvoice(Id invoiceId) {
    List<Invoice__c> rows = [
        SELECT Id, Amount__c, Customer__c FROM Invoice__c WHERE Id = :invoiceId WITH USER_MODE
    ];
    if (rows.isEmpty()) {
        throw new AuraHandledException('Record not found');
    }
    return rows[0];
}
```

## Mass assignment (X6)

```apex
// VULNERABLE: client controls every field, including OwnerId / Approved__c
@AuraEnabled
public static void saveLead(String payload) {
    Lead l = (Lead) JSON.deserialize(payload, Lead.class);
    upsert l;
}

// FIXED: DTO with only the fields the UI may set
public class LeadInput {
    @AuraEnabled public String lastName;
    @AuraEnabled public String company;
    @AuraEnabled public String email;
}

@AuraEnabled
public static Id saveLead(LeadInput input) {
    Lead l = new Lead(LastName = input.lastName, Company = input.company, Email = input.email);
    insert as user l;
    return l.Id;
}
```

## Credentials and callouts (P2)

```apex
// VULNERABLE: secret stored in a custom setting and handled in code
String key = Integration_Settings__c.getOrgDefaults().Api_Key__c;
req.setEndpoint('https://api.vendor.com/v1/orders');
req.setHeader('Authorization', 'Bearer ' + key);

// FIXED: Named Credential + External Credential own the endpoint and the auth header
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Vendor_API/v1/orders');
req.setMethod('GET');
HttpResponse res = new Http().send(req);
```
Set up the Named/External Credential with the `integration:integration-connectivity-generate` skill; inbound OAuth
clients with `integration:integration-connectivity-connected-app-configure` (External Client Apps).

## Visualforce XSS / CSRF / redirect (X1, X3, X4)

```html
<!-- VULNERABLE -->
<script>var q = '{!$CurrentPage.parameters.q}';</script>
<apex:outputText value="{!description}" escape="false"/>
<apex:page controller="InvoiceCtrl" action="{!markViewed}">   <!-- DML on GET -->

<!-- FIXED -->
<script>var q = '{!JSENCODE($CurrentPage.parameters.q)}';</script>
<apex:outputText value="{!description}"/>
<!-- move markViewed to an <apex:commandButton action="{!markViewed}"/> (POST with CSRF token) -->
```

```apex
// Open redirect: only allow relative, same-org paths
String target = ApexPages.currentPage().getParameters().get('retURL');
if (String.isBlank(target) || !target.startsWith('/') || target.startsWith('//')) {
    target = '/home/home.jsp';
}
return new PageReference(target);
```

## LWC / Aura XSS (X2)

```js
// VULNERABLE
this.template.querySelector('.msg').innerHTML = this.message;

// FIXED: let the template bind text, or use a base component for rich text
// <template><p class="msg">{message}</p></template>
// <lightning-formatted-rich-text value={message}></lightning-formatted-rich-text>
```
Aura: replace `<aura:unescapedHtml value="{!v.html}"/>` with `<lightning:formattedRichText value="{!v.html}"/>`.

## Flows (P10, X13)

`<runInMode>SystemModeWithoutSharing</runInMode>` on a screen flow used by a site → anyone can run record
lookups/updates across the org. Use `DefaultMode` (user context) and grant the minimum object access; if
elevation is required, isolate it in a subflow and document the justification in the flow description.
