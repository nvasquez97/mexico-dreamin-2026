// Assigns the site guest user its permission set (public Apex + EntregaYa credential principal) and gives the
// running admin the support and integration sets (so the admin can act as an agent and simulate EntregaYa).
// Safe to re-run.
Id guestId = [SELECT GuestUserId FROM Site WHERE UrlPathPrefix = 'rutacargo' LIMIT 1].GuestUserId;
Map<String, Id> sets = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('RutaCargo_Public_Site', 'RutaCargo_Support', 'RutaCargo_EntregaYa_Integration')]) {
    sets.put(ps.Name, ps.Id);
}
Set<String> existing = new Set<String>();
for (PermissionSetAssignment a : [SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE PermissionSetId IN :sets.values()]) {
    existing.add(a.AssigneeId + ':' + a.PermissionSetId);
}
List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
for (String n : sets.keySet()) {
    Id who = n == 'RutaCargo_Public_Site' ? guestId : UserInfo.getUserId();
    if (!existing.contains(who + ':' + sets.get(n))) {
        toAdd.add(new PermissionSetAssignment(AssigneeId = who, PermissionSetId = sets.get(n)));
    }
}
insert toAdd;
System.debug('ASSIGNED ' + toAdd.size());
