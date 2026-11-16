-- S1-b reverse Build02A only; Build01 authority/audit preserved.
DROP FUNCTION core10.build02a_set_approval_policy_v1(bigint,uuid,text[],text[],timestamptz,text,bigint);
DROP FUNCTION core10.can_approval_action_v1(bigint,bigint,text);
ALTER TABLE core10.access_change_events_v1 DROP CONSTRAINT access_change_events_v1_command_check;
ALTER TABLE core10.access_change_events_v1 ADD CONSTRAINT access_change_events_v1_command_check
 CHECK (command IN ('business_member.grant','business_member.revoke','site_grant.grant',
                    'site_grant.revoke','setup.business','setup.site'));
ALTER TABLE core10.business_members
 DROP COLUMN approval_valid_until,
 DROP COLUMN approval_denied_actions,
 DROP COLUMN approval_actions;
