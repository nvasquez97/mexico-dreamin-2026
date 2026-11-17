/**
 * REQ-004: EntregaYa pushes one status change per call.
 *
 *   POST /services/apexrest/entregaya/v1/status
 *   {"trackingNumber":"RC000001042","status":"Out for delivery","location":"Monterrey, NL",
 *    "timestamp":"2026-11-20T10:00:00-06:00","proofId":null}
 *
 * BR-04: only the integration user may call it. Besides the Apex class access in the permission set,
 * the caller must hold the EntregaYa_Integration custom permission, checked below.
 */
@RestResource(urlMapping='/entregaya/v1/status')
global without sharing class EntregaYaStatusResource {
    private class BadRequestException extends Exception {
    }

    @HttpPost
    global static void receive() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        if (!FeatureManagement.checkPermission('EntregaYa_Integration')) {
            respond(res, 403, new Map<String, Object>{ 'error' => 'Not authorized to send status updates.' });
            return;
        }
        try {
            Map<String, Object> out = apply(RestContext.request.requestBody == null ? '' : RestContext.request.requestBody.toString());
            respond(res, 200, out);
        } catch (BadRequestException e) {
            respond(res, e.getMessage().startsWith('Shipment not found') ? 404 : 400, new Map<String, Object>{ 'error' => e.getMessage() });
        }
    }

    @TestVisible
    private static Map<String, Object> apply(String body) {
        Map<String, Object> m;
        try {
            m = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            throw new BadRequestException('The body is not valid JSON.');
        }
        String tn = text(m, 'trackingNumber');
        String status = text(m, 'status');
        String tsRaw = text(m, 'timestamp');
        if (tn == null) {
            throw new BadRequestException('trackingNumber is required.');
        }
        if (status == null) {
            throw new BadRequestException('status is required.');
        }
        if (tsRaw == null) {
            throw new BadRequestException('timestamp is required (ISO 8601, e.g. 2026-11-20T10:00:00-06:00).');
        }
        List<String> valid = new List<String>();
        for (Schema.PicklistEntry pe : Shipment__c.Status__c.getDescribe().getPicklistValues()) {
            valid.add(pe.getValue());
        }
        if (!new Set<String>(valid).contains(status)) {
            throw new BadRequestException('Invalid status "' + status + '". Valid statuses: ' + String.join(valid, ', ') + '.');
        }
        Datetime ts;
        try {
            ts = (Datetime) JSON.deserialize('"' + tsRaw.replace('"', '') + '"', Datetime.class);
        } catch (Exception e) {
            throw new BadRequestException('timestamp is not a valid ISO 8601 date and time.');
        }
        if (ts == null) {
            throw new BadRequestException('timestamp is not a valid ISO 8601 date and time.');
        }

        // Row lock: concurrent updates for the same parcel are serialized, so AC-004.4 always compares
        // against the latest committed timestamp.
        List<Shipment__c> rows = [
            SELECT Id, Name, Status__c, Last_Update__c, Last_Location__c FROM Shipment__c WHERE Name = :tn WITH SYSTEM_MODE LIMIT 1 FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw new BadRequestException('Shipment not found: ' + tn);
        }
        Shipment__c s = rows[0];
        if (s.Last_Update__c != null && ts < s.Last_Update__c) { // AC-004.4
            return new Map<String, Object>{ 'result' => 'ignored', 'reason' => 'Older than the last recorded update.', 'trackingNumber' => s.Name };
        }
        s.Status__c = status;
        s.Last_Update__c = ts;
        String location = text(m, 'location');
        if (location != null) {
            s.Last_Location__c = location.left(120);
        }
        if (status == 'Delivered') { // AC-004.2
            s.Delivered_At__c = ts;
            String proofId = text(m, 'proofId');
            if (proofId != null) {
                s.Proof_Id__c = proofId.left(80);
            }
        }
        Database.update(s, AccessLevel.SYSTEM_MODE);
        return new Map<String, Object>{ 'result' => 'updated', 'trackingNumber' => s.Name, 'status' => s.Status__c };
    }

    private static String text(Map<String, Object> m, String key) {
        Object v = m.get(key);
        if (v == null) {
            return null;
        }
        String s = String.valueOf(v).trim();
        return s == '' ? null : s;
    }

    private static void respond(RestResponse res, Integer code, Map<String, Object> body) {
        res.statusCode = code;
        res.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
