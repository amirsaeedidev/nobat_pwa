-- Keep appointment.price_toman as the pre-discount total and discount_toman as
-- the discount amount. The payable amount is price_toman - discount_toman.
do $$
declare
  v_definition text;
  v_updated text;
  v_old text;
  v_new text := 'coalesce(sum(coalesce(es.custom_price_toman,s.price_toman)),0)';
begin
  v_definition := pg_get_functiondef(
    'public.create_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text,text,text)'::regprocedure
  );
  v_old := $old$coalesce(sum(coalesce(es.custom_price_toman,
      case when s.discount_price_toman is not null
        and (p_starts_at at time zone b.timezone)::date
          between coalesce(s.discount_starts_on,'-infinity'::date)
              and coalesce(s.discount_ends_on,'infinity'::date)
        then s.discount_price_toman else s.price_toman end)),0)$old$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch create appointment list-price total'; end if;
  execute v_updated;

  v_definition := pg_get_functiondef(
    'public.update_appointment(uuid,uuid,uuid,timestamp with time zone,uuid[],text)'::regprocedure
  );
  v_old := $old$coalesce(sum(coalesce(es.custom_price_toman,
        case when s.discount_price_toman is not null
          and (p_starts_at at time zone b.timezone)::date
            between coalesce(s.discount_starts_on,'-infinity'::date)
                and coalesce(s.discount_ends_on,'infinity'::date)
          then s.discount_price_toman else s.price_toman end)),0)$old$;
  v_updated := replace(v_definition,v_old,v_new);
  if v_updated=v_definition then raise exception 'Could not patch update appointment list-price total'; end if;
  execute v_updated;
end;
$$;
