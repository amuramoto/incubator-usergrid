package org.apache.usergrid.persistence.collection.mvcc.stage.impl;


import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.apache.commons.lang3.reflect.FieldUtils;

import org.apache.usergrid.persistence.collection.exception.CollectionRuntimeException;
import org.apache.usergrid.persistence.collection.mvcc.stage.Stage;
import org.apache.usergrid.persistence.collection.mvcc.stage.ExecutionContext;
import org.apache.usergrid.persistence.collection.service.TimeService;
import org.apache.usergrid.persistence.collection.service.UUIDService;
import org.apache.usergrid.persistence.collection.util.Verify;
import org.apache.usergrid.persistence.model.entity.Entity;

import com.google.common.base.Preconditions;
import com.google.inject.Inject;
import com.google.inject.Singleton;


/**
 * This is the first stage and should be invoked immediately when a new entity create is started. No UUIDs should be
 * present, and this should set the entityId, version, created, and updated dates
 */
@Singleton
public class Create implements Stage {

    private static final Logger LOG = LoggerFactory.getLogger( Create.class );


    private final TimeService timeService;
    private final UUIDService uuidService;


    @Inject
    public Create( final TimeService timeService, final UUIDService uuidService ) {
        Preconditions.checkNotNull( timeService, "timeService is required" );
        Preconditions.checkNotNull( uuidService, "uuidService is required" );


        this.timeService = timeService;
        this.uuidService = uuidService;
    }


    /**
     * Create the entity Id  and inject it, as well as set the timestamp versions
     *
     * @param executionContext The context of the current write operation
     */
    @Override
    public void performStage( final ExecutionContext executionContext ) {

        final Entity entity = executionContext.getMessage( Entity.class );

        Preconditions.checkNotNull( entity, "Entity is required in the new stage of the mvcc write" );

        Verify.isNull( entity.getUuid(), "A new entity should not have an id set.  This is an update operation" );


        final UUID entityId = uuidService.newTimeUUID();
        final UUID version = entityId;
        final long created = timeService.getTime();


        try {
            FieldUtils.writeDeclaredField( entity, "uuid", entityId, true );
        }
        catch ( Throwable t ) {
            LOG.error( "Unable to set uuid.  See nested exception", t );
            throw new CollectionRuntimeException( "Unable to set uuid.  See nested exception", t );
        }

        entity.setVersion( version );
        entity.setCreated( created );
        entity.setUpdated( created );

        //set the updated entity for the next stage
        executionContext.setMessage( entity );
        executionContext.proceed();
    }
}