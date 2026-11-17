/**
 * REQ-004 — endpoint EntregaYa calls for every status change.
 *
 *   POST /services/apexrest/entregaya/v1/status-updates
 *   Authorization: Bearer <access token obtained with OAuth 2.0 client credentials>
 *   {"trackingNumber":"RC000001042","status":"Out for delivery","location":"Monterrey, NL",
 *    "timestamp":"2026-11-20T10:00:00-06:00","proofId":null}
 *
 * Responses (JSON):
 *   200 {"result":"UPDATED"|"IGNORED", "trackingNumber", "status", "message"}
 *   400 {"errorCode":"INVALID_REQUEST"|"INVALID_STATUS"|"INVALID_TIMESTAMP", "message"}
 *   404 {"errorCode":"TRACKING_NUMBER_NOT_FOUND", "message"}
 *
 * BR-04: only the EntregaYa integration user has access to this class (permission set
 * EntregaYa_Integration); the platform rejects anyone else before this code runs.
 */
@RestResource(urlMapping='/entregaya/v1/status-updates')
global without sharing class EntregaYaStatusResource {
  @HttpPost
  global static void receive() {
    RestResponse response = RestContext.response;
    response.addHeader('Content-Type', 'application/json');
    Map<String, Object> body = new Map<String, Object>();
    try {
      ShipmentStatusUpdateService.StatusUpdate change = parse(
        RestContext.request.requestBody
      );
      ShipmentStatusUpdateService.Outcome outcome = ShipmentStatusUpdateService.apply(
        change
      );
      response.statusCode = 200;
      body.put('result', outcome.result);
      body.put('trackingNumber', outcome.trackingNumber);
      body.put('status', outcome.status);
      body.put('message', outcome.message);
    } catch (ShipmentStatusUpdateService.UpdateException e) {
      response.statusCode = e.httpStatus;
      body.put('errorCode', e.code);
      body.put('message', e.getMessage());
    }
    response.responseBody = Blob.valueOf(JSON.serialize(body));
  }

  private static ShipmentStatusUpdateService.StatusUpdate parse(
    Blob requestBody
  ) {
    String json = requestBody == null ? '' : requestBody.toString();
    if (String.isBlank(json)) {
      throw new ShipmentStatusUpdateService.UpdateException(
        400,
        ShipmentStatusUpdateService.ERR_INVALID_REQUEST,
        'The request body is empty.'
      );
    }
    try {
      return (ShipmentStatusUpdateService.StatusUpdate) System.JSON.deserialize(
        json,
        ShipmentStatusUpdateService.StatusUpdate.class
      );
    } catch (Exception e) {
      throw new ShipmentStatusUpdateService.UpdateException(
        400,
        ShipmentStatusUpdateService.ERR_INVALID_REQUEST,
        'The request body is not valid JSON: ' + e.getMessage()
      );
    }
  }
}
