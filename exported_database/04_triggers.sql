-- Triggers

CREATE TRIGGER on_professional_user_created AFTER INSERT ON public.users FOR EACH ROW EXECUTE FUNCTION handle_new_professional();

CREATE TRIGGER update_location_timestamp_trigger BEFORE UPDATE ON public.professional_profiles FOR EACH ROW EXECUTE FUNCTION update_location_timestamp_function();

CREATE TRIGGER update_safety_checks_updated_at BEFORE UPDATE ON public.safety_checks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_location_verifications_updated_at BEFORE UPDATE ON public.location_verifications FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER after_job_completed_record_earnings AFTER UPDATE OF current_stage ON public.jobs FOR EACH ROW WHEN ((new.current_stage = 'Completed'::text)) EXECUTE FUNCTION record_professional_earnings();

CREATE TRIGGER after_job_completed AFTER UPDATE OF current_stage ON public.jobs FOR EACH ROW WHEN ((new.current_stage = 'Completed'::text)) EXECUTE FUNCTION update_professional_stats();

CREATE TRIGGER job_stage_change_trigger AFTER UPDATE OF current_stage ON public.jobs FOR EACH ROW EXECUTE FUNCTION record_job_stage_change();

CREATE TRIGGER update_site_photos_updated_at BEFORE UPDATE ON public.site_photos FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER expire_broadcasts_trigger BEFORE INSERT OR UPDATE ON public.job_broadcasts FOR EACH ROW EXECUTE FUNCTION expire_broadcasts_function();

CREATE TRIGGER validate_broadcast_response_trigger BEFORE INSERT ON public.professional_responses FOR EACH ROW EXECUTE FUNCTION validate_broadcast_response_function();

