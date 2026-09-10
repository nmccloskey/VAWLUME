function tests = test_usvseg_import
%TEST_USVSEG_IMPORT Database-facing USVSEG plan/apply contract.
tests=functiontests(localfunctions);
end

function testDryRunIsReadOnlyAndSettingsAbsenceIsExplicit(testCase)
[f,c]=fixture(); %#ok<ASGLU>
before=counts(f.conn); result=plan(f,defaultSpec());
verifyEqual(testCase,result.status,"planned"); verifyFalse(testCase,result.committed);
verifyEqual(testCase,result.extractor.extractor_name,"USVSEG");
verifyEqual(testCase,result.settings.status,"unavailable");
verifyFalse(testCase,result.settings.verified_run_configuration);
verifyTrue(testCase,any(contains(result.warnings,"USVSEG_SETTINGS_UNAVAILABLE")));
verifyEqual(testCase,result.event_population.planned_detection_count,2);
verifyEqual(testCase,counts(f.conn),before); clear c
end

function testApplyPreservesPopulationMeasurementsAndUnmappedValues(testCase)
[f,c]=fixture(); %#ok<ASGLU>
result=apply(f,defaultSpec());
verifyTrue(testCase,result.committed); verifyEqual(testCase,result.applied_counts.detections,2);
verifyEqual(testCase,result.applied_counts.event_measurements,14);
verifyEqual(testCase,result.applied_counts.unmapped_source_values,2);
rows=fetch(f.conn,"SELECT native_event_id,start_time_s,end_time_s,timing_basis,event_subtype FROM detections ORDER BY detection_id");
verifyEqual(testCase,string(rows.native_event_id),["1";"2"]);
verifyEqual(testCase,double(rows.start_time_s),[.1;.25],AbsTol=1e-12);
verifyEqual(testCase,double(rows.end_time_s),[.145;.301],AbsTol=1e-12);
verifyEqual(testCase,unique(string(rows.timing_basis)),"profile_selected_event_geometry");
duration=measurement(f.conn,"1","duration");
verifyEqual(testCase,string(duration.native_raw_token),"45.0");
verifyEqual(testCase,double(duration.native_value_real),45,AbsTol=1e-12);
verifyEqual(testCase,double(duration.canonical_value_real),.045,AbsTol=1e-12);
peak=measurement(f.conn,"1","maxfreq");
verifyEqual(testCase,double(peak.native_value_real),72.5,AbsTol=1e-12);
verifyEqual(testCase,double(peak.canonical_value_real),72500,AbsTol=1e-9);
unknown=fetch(f.conn,"SELECT native_field_name,raw_value_text,source_locator,reason_unmapped FROM unmapped_source_values ORDER BY unmapped_value_id");
verifyEqual(testCase,string(unknown.native_field_name),["future_metric";"future_metric"]);
verifyEqual(testCase,string(unknown.raw_value_text),["0007.50";"0008.25"]);
verifyEqual(testCase,string(unknown.source_locator),["row=1; column=future_metric";"row=2; column=future_metric"]);
verifyEqual(testCase,count(f.conn,"curation_events"),0); verifyEqual(testCase,count(f.conn,"classification_assignments"),0);
verifyEqual(testCase,height(fetch(f.conn,"PRAGMA foreign_key_check")),0); clear c
end

function testOptionalSettingsArtifactIsWeakEvidenceNotRunProfile(testCase)
[f,c]=fixture(); %#ok<ASGLU>
prm=struct(fftsize=512,freqmin=30); settingsPath=fullfile(f.scratch,"settings","usvseg_prm.mat");
makeParent(settingsPath); save(char(settingsPath),'prm');
spec=defaultSpec(); spec.settings=struct(artifact_path=settingsPath);
result=apply(f,spec);
verifyEqual(testCase,result.settings.status,"captured_weak");
verifyFalse(testCase,result.settings.verified_run_configuration);
row=result.artifacts(result.artifacts.role=="extractor_settings",:);
verifyEqual(testCase,height(row),1); verifyTrue(testCase,row.is_native);
metadata=jsondecode(char(row.metadata_json));
verifyEqual(testCase,string(metadata.evidence_strength),"weak_not_run_scoped");
verifyTrue(testCase,contains(string(metadata.evidence_scope),"not_verified"));
run=fetch(f.conn,"SELECT IFNULL(settings_profile_version_id,-1) AS settings_id,IFNULL(notes,'') AS notes FROM extraction_runs");
verifyEqual(testCase,double(run.settings_id),-1); verifyTrue(testCase,contains(string(run.notes),"captured_weak")); clear c
end

function testInvalidOrMissingSettingsEvidenceIsRefusedWithoutWrites(testCase)
[f,c]=fixture(); %#ok<ASGLU>
before=counts(f.conn); spec=defaultSpec(); spec.settings=struct(artifact_path=fullfile(f.scratch,"missing","usvseg_prm.mat"));
verifyError(testCase,@() apply(f,spec),"vawlume:ingest:UsvsegSettingsNotFound");
wrong=fullfile(f.scratch,"settings","usvseg_prm.mat"); makeParent(wrong); other=1; save(char(wrong),'other');
spec.settings=struct(artifact_path=wrong);
verifyError(testCase,@() apply(f,spec),"vawlume:ingest:UsvsegSettingsInvalid");
verifyEqual(testCase,counts(f.conn),before); clear c
end

function testZeroDetectionExportStillCommitsRunProvenance(testCase)
[f,c]=fixture(); %#ok<ASGLU>
writeCsv(f.export_path,false,false); result=apply(f,defaultSpec());
verifyTrue(testCase,result.committed); verifyEqual(testCase,result.event_population.planned_detection_count,0);
verifyEqual(testCase,count(f.conn,"extraction_runs"),1); verifyEqual(testCase,count(f.conn,"detections"),0);
verifyEqual(testCase,count(f.conn,"extraction_run_artifacts"),1); clear c
end

function testVersionAndNativeIdentityGuards(testCase)
[f,c]=fixture(); %#ok<ASGLU>
spec=rmfield(defaultSpec(),"extractor_version"); verifyError(testCase,@() plan(f,spec),"vawlume:ingest:UsvsegVersionRequired");
spec=defaultSpec(); spec.extractor_version="0.8r7"; verifyError(testCase,@() plan(f,spec),"vawlume:ingest:UsvsegVersionIncompatible");
writeLines(f.export_path,[header(true);"1,0.1000,0.1450,45.0,72.500,-18.2,61.250,0.1234,0007.50";"1,0.2500,0.3010,51.0,74.000,-19.1,63.125,0.1111,0008.25"]);
verifyError(testCase,@() apply(f,defaultSpec()),"vawlume:ingest:UsvsegEventValidationFailed"); clear c
end

function testUnsupportedRoutedAnnotationIsNeverDiscarded(testCase)
[f,c]=fixture(); %#ok<ASGLU>
profilePath=fullfile(f.repo_root,"config","01_mapping_profiles","extractors","usvseg","usvseg_output_mapping_profile.json");
loaded=vawlume.source_mapping.loadProfile(profilePath,ExpectedKind="extractor_output",RepoRoot=f.repo_root);
mapping=loaded.document.field_mappings{1}; mapping.source_field="review"; mapping.canonical_field="review_state";
mapping.data_type="string"; mapping.semantic_role="curation_state";
loaded.document.field_mappings{end+1}=mapping;
loaded.profile_documents{1}=loaded.document;
loaded.field_mappings=loaded.document.field_mappings;
writeLines(f.export_path,[header(true)+",review";"1,0.1000,0.1450,45.0,72.500,-18.2,61.250,0.1234,0007.50,accepted"]);
verifyError(testCase,@() vawlume.ingest.usvseg(f.conn,f.export_path,ref(),defaultSpec(), ...
    RepoRoot=f.repo_root,ArtifactRoot=f.artifact_root,Profile=loaded), ...
    "vawlume:ingest:UsvsegUnsupportedEventEvidence"); clear c
end

function testRerunReusesEverythingAndStoredDriftConflicts(testCase)
[f,c]=fixture(); %#ok<ASGLU>
apply(f,defaultSpec()); after=counts(f.conn); second=apply(f,defaultSpec());
verifyEqual(testCase,second.applied_counts.detections,0); verifyEqual(testCase,second.applied_counts.reused_detections,2);
verifyEqual(testCase,second.applied_counts.reused_unmapped_source_values,2); verifyEqual(testCase,counts(f.conn),after);
execute(f.conn,"UPDATE event_measurements SET canonical_value_real=999 WHERE event_measurement_id=(SELECT MIN(event_measurement_id) FROM event_measurements)");
conflicted=plan(f,defaultSpec()); verifyTrue(testCase,conflicted.has_conflicts);
verifyTrue(testCase,any(contains(conflicted.conflicts,"stored value differs"))); clear c
end

function testLateFailureRollsBackWholeGraph(testCase)
[f,c]=fixture(); %#ok<ASGLU>
before=counts(f.conn); execute(f.conn,"CREATE TRIGGER fail_unmapped BEFORE INSERT ON unmapped_source_values BEGIN SELECT RAISE(ABORT,'late failure'); END");
verifyError(testCase,@() applyExpectingFailure(f),"phase14:InducedFailure");
verifyEqual(testCase,counts(f.conn),before); verifyEqual(testCase,string(f.conn.AutoCommit),"on"); clear c
end

function testImporterIsExtractorSeparated(testCase)
root=repoRootPath(); files=[fullfile(root,"src","+vawlume","+ingest","usvseg.m"); string(fullfile(root,"src","+vawlume","+ingest","private"))+"/usvsegBuildPlan.m"; string(fullfile(root,"src","+vawlume","+ingest","private"))+"/usvsegResolveEvents.m"];
text=""; for file=files', text=text+lower(string(fileread(file))); end
verifyFalse(testCase,contains(text,"mupet")); verifyFalse(testCase,contains(text,"deepsqueak"));
end

function [f,cleanup]=fixture()
root=repoRootPath(); addpath(fullfile(root,"src")); scratch=string(tempname); mkdir(scratch);
db=fullfile(scratch,"usvseg.sqlite"); copyfile(template(root),db); conn=sqlite(char(db));
cleanup=onCleanup(@() cleanupFixture(conn,scratch,root));
execute(conn,"INSERT INTO projects(project_key,project_name) VALUES('proj-a','Project A')");
execute(conn,"INSERT INTO source_files(project_id,file_role,path_or_uri,relative_path,filename) VALUES(1,'recording_audio','audio/REC_A.wav','audio/REC_A.wav','REC_A.wav')");
execute(conn,"INSERT INTO recordings(project_id,source_file_id,native_recording_id) VALUES(1,1,'REC_A')");
exportPath=fullfile(scratch,"exports","REC_A_dat.csv"); writeCsv(exportPath,true,true);
f=struct(conn=conn,repo_root=root,scratch=scratch,artifact_root=scratch,export_path=exportPath);
end
function path=template(root)
persistent value
if isempty(value)||~isfile(value), value=string(tempname)+".sqlite"; conn=sqlite(char(value),"create"); c=onCleanup(@() close(conn)); vawlume.db.applySchema(conn,fullfile(root,"schema","schema.sql")); vawlume.db.registerBuiltinSemantics(conn,root); delete(c); end
path=value;
end
function result=plan(f,spec), result=vawlume.ingest.usvseg(f.conn,f.export_path,ref(),spec,RepoRoot=f.repo_root,ArtifactRoot=f.artifact_root); end
function result=apply(f,spec), result=vawlume.ingest.usvseg(f.conn,f.export_path,ref(),spec,RepoRoot=f.repo_root,ArtifactRoot=f.artifact_root,Apply=true); end
function value=ref(), value=struct(project_key="proj-a",source_relative_path="audio/REC_A.wav"); end
function value=defaultSpec(), value=struct(run_key="usvseg-run-1",extractor_version="0.9r2",run_label="USVSEG run 1"); end
function writeCsv(path,withRows,withExtra)
lines=header(withExtra); if withRows, suffix=""; if withExtra,suffix=",0007.50";end; lines=[lines;"1,0.1000,0.1450,45.0,72.500,-18.2,61.250,0.1234"+suffix;"2,0.2500,0.3010,51.0,74.000,-19.1,63.125,0.1111"+replace(suffix,"0007.50","0008.25")]; end; writeLines(path,lines);
end
function value=header(extra), value="#,start,end,duration,maxfreq,maxamp,meanfreq,cvfreq"; if extra,value=value+",future_metric";end, end
function writeLines(path,lines), makeParent(path); id=fopen(path,"w"); assert(id>=0); c=onCleanup(@() fclose(id)); fprintf(id,"%s\n",lines); delete(c); end
function makeParent(path), parent=fileparts(path); if ~isfolder(parent),mkdir(parent);end, end
function row=measurement(conn,id,name), row=fetch(conn,"SELECT em.native_raw_token,em.native_value_real,em.canonical_value_real FROM event_measurements em JOIN detections d ON d.detection_id=em.detection_id JOIN extractor_features xf ON xf.extractor_feature_id=em.extractor_feature_id WHERE d.native_event_id='"+id+"' AND xf.native_name='"+name+"'"); end
function value=counts(conn), names=["artifacts","extraction_runs","extraction_run_inputs","extraction_run_artifacts","detections","event_measurements","unmapped_source_values"]; value=struct(); for name=names,value.(name)=count(conn,name);end, end
function value=count(conn,name), row=fetch(conn,"SELECT COUNT(*) AS n FROM "+name); value=double(row.n(1)); end
function applyExpectingFailure(f), try apply(f,defaultSpec()); catch e, error("phase14:InducedFailure","%s",e.message); end, error("phase14:InducedFailure","Trigger did not fail."); end
function cleanupFixture(conn,scratch,root), try close(conn);catch,end; if isfolder(scratch),rmdir(scratch,"s");end; rmpath(fullfile(root,"src")); end
function root=repoRootPath(), root=fileparts(fileparts(fileparts(mfilename("fullpath")))); end
