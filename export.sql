
CREATE OR REPLACE FUNCTION get_paginated_results(page_number INT, page_size INT)
RETURNS JSON AS $$
DECLARE
    offset_value INT;
    result JSON;
BEGIN
    offset_value := (page_number - 1) * page_size;
SELECT
    json_agg(row_to_json(t1))
    into result from (
	select 
	i.uuid,
	json_build_object('$date', i.created_at::TIMESTAMPTZ) as "createdAt",
	json_build_object('$date', i.updated_at::TIMESTAMPTZ) as "updatedAt",
	i.class,
	case when
	compFile.filename is null then null
	else json_build_object(
		'filename', compFile.filename,
		'mime', compFile.mime,
		'height', compFile.height,
		'width', compFile.width,
		'url', compFile.url,
		'uri', compFile.uri,
		'size', compFile.size
	)end as info,
	COALESCE(
		(
			SELECT array_to_json(array_agg(metas))
			FROM (
				SELECT
					meta.key,
					meta.value
				FROM components_image_metadata meta
				JOIN images_components comp ON meta.id = comp.component_id
				WHERE comp.entity_id = i.id AND comp.field = 'metadata'
				ORDER BY meta.id ASC
			) metas
		), '[]'::json
	) metadata,
	json_build_object(
		'uuid', a.uuid,
		'status', a.status,
		'createdAt',json_build_object('$date', a.created_at::TIMESTAMPTZ),
		'updatedAt',json_build_object('$date', a.updated_at::TIMESTAMPTZ),
		'predictions', (
                    SELECT array_to_json(array_agg(preds))
                    FROM (
                      SELECT
						p.id,
						p.name,
						p.confidence,
						p.scope,
						p.points,
						p.is_false_positive as "isFalsePositive",
						(SELECT array_to_json(array_agg(attr))
                         FROM (
                             SELECT 
                                 att.id,
                                 att.key,
                                 att.value,
                                 att.confidence
                             FROM components_object_attributes att
                             JOIN predictions_components pcomp ON att.id = pcomp.component_id
							  WHERE p.id = pcomp.entity_id
                         ) attr) as attrs
                      FROM predictions p
						join analyses_predictions_links ap on a.id = ap.analysis_id
						where p.id = ap.prediction_id
						ORDER BY ap.prediction_order
			) preds
		)
	) as analysis,
	case 
		when u.id is null then null
		else
	json_build_object(
	'id', u.id,
	'firstname', u.firstname,
	'lastname', u.lastname,
	'email', u.email
	)end AS user,	
	case
		when ic.uuid is null then null
		else json_build_object(
		'id', ic.id,
		'uuid', ic.uuid, 
		'externalId', ic.external_id,
		'name', ic.name,
		'description', ic.description,
		'status', ic.status,
		'createdAt',json_build_object('$date', ic.created_at::TIMESTAMPTZ),
		'updatedAt',json_build_object('$date', ic.updated_at::TIMESTAMPTZ),
	     'project', (
        SELECT json_build_object(
            'id', projs.id,
            'uuid', projs.uuid,
            'name', projs.name,
            'description', projs.description,
            'status', projs.status,
            'createdAt', json_build_object('$date', projs.created_at::TIMESTAMPTZ),
            'updatedAt', json_build_object('$date', projs.updated_at::TIMESTAMPTZ),
            'objective', projs.objective
        )
        FROM projects projs
        JOIN image_collections_project_links icolPrjsL ON ic.id = icolPrjsL.image_collection_id
        WHERE projs.id = icolPrjsL.project_id
    ))end as "imageCollection",
	json_build_object(
	'id', c.id,
	'name', c.name
	) AS company,
	fimg.analysis_duration as "analysisDuration"
	from images i
	left join images_user_links iu on i.id = iu.image_id
	left join images_company_links icomp on i.id = icomp.image_id
	inner join images_components comp on i.id = comp.entity_id
	left join images_collection_links icolL on i.id = icolL.image_id
	left join analyses_image_links ai on i.id = ai.image_id
	inner join components_image_image_details compFile on compFile.id = comp.component_id AND comp.field = 'info'
	left join image_collections ic on icolL.image_collection_id = ic.id 
	left join up_users u on u.id  = iu."user_id" 
	left join companies c on c.id  = icomp."company_id" 
	left join analyses a on a.id = ai.analysis_id
	left join flat_images fimg on i.id = fimg.image_id
	order by i.created_at asc 
	LIMIT page_size OFFSET offset_value
	) 
t1;



    RETURN result;
END;
$$ LANGUAGE plpgsql;


