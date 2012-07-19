require 'omf-aggmgr/ogs/gridService'
require 'omf-aggmgr/ogs_confine/confinePortal'
require 'omf-aggmgr/ogs_inventory/mySQLInventory'
require 'omf-aggmgr/ogs_inventory/inventory'
require 'omf-aggmgr/ogs_sliceManager/sliceManager'

class ConfineService < GridService

  # used to register/mount the service, the service's url will be based on it
  name 'confine'
  description 'Service to to access the CONFINE portal'

  @@config = nil
  @@portal = nil
  @@slicemgr = nil

  PUBSUB_DOMAIN = 'omf-am.local'

  def self.getPortal
   # Just reuse it if it already exist
   if ( @@portal == nil )
     # Otherwise create it
     @@portal = Confine::Portal.new
   end
   @@portal
  end

  def self.getSliceMgr
   # Just reuse it if it already exist
   if ( @@slicemgr == nil )
     # Otherwise create it
     @@slicemgr = SliceManagerService.new
   end
   @@slicemgr
  end

  #
  # Configure the service through a hash of options
  # Also lists all configuration default that should be in confine.yaml
  # If defaults are missing, this is reported as an error and hardcoded defaults are taken as default.
  #
  # - config = the Hash holding the config parameters for this service
  #
  def self.configure(config)
    # Check if default sliver configuration is correct
    if ((dc = config['sliver']) == nil)
      raise ServiceError, "Missing 'sliver' configuration in confine.yaml"
    end
    # Check if db configuration is correct
    getTestbedConfig(nil, config)
    @@config = config
  end

  #
  # Do generic database stuff
  #
  def self.doDB
	begin
 		# Query the inventory
		conf = getTestbedConfig(nil, @@config)
      		inv = InventoryService.getInv(conf)
      		yield(inv)
    	rescue Exception => ex
      		error "Inventory - Error connecting to the Inventory Database - '#{ex}''"
      		raise HTTPStatus::InternalServerError
    	end
  end

  #
  # Implements allocating a slice at the CONFINE testbed
  #
  s_description "Allocate a slice in the CONFINE testbed"
  service 'allocateSlice' do
	result = getPortal.createSlice
	doDB do |inv|
		resultTestbed = inv.addTestbed(result['testbed'])
	end

	# SliceManagerService.createSlice(result['testbed'],PUBSUB_DOMAIN)

	replyXML = InventoryService.buildXMLReply("SLICE", result, "Failed to allocate a new slice.") { |root,result|
      		InventoryService.addXMLElement(root, "SLICE_ID", "#{result['sliceid']}")
		InventoryService.addXMLElement(root, "DOMAIN", "#{result['testbed']}")
    	}
    	replyXML
  end

  # Make up the location for the database
  # Use the information provided by the CONFINE portal
  def self.makeDBLocation(location)
	dbLocation = Hash.new
	# Fill in that received from CONFINE Portal
	dbLocation['name'] = location['name']
	dbLocation['x'] = location['x']
	dbLocation['y'] = location['y']
	dbLocation['z'] = location['z']
	
	# Fill in the db id of the location of this node added in the db
	doDB do |inv|
		id = inv.getTestbedId(location['testbedname'])
		dbLocation['testbed_id'] = id
	end
	dbLocation
  end

  # Make up the node for the database
  # Use the information provided by the CONFINE portal
  def self.makeDBNode(sliver)
	node = Hash.new
	# Fill in that received from CONFINE Portal
	node['control_ip'] = sliver['node']['control_ip']
	node['control_mac'] = sliver['node']['control_mac']
	node['hostname'] = sliver['node']['hostname']
	node['hrn'] = sliver['node']['hrn']

	# Fill in the db id of the location of this node added in the db
	doDB do |inv|
		id = inv.getLocationId(sliver['location']['name'], 
					sliver['location']['x'],
					sliver['location']['y'], 
					sliver['location']['z'])
		node['location_id'] = id        
	end
	node
  end

  #
  # Implements allocating a slivergroup at the CONFINE testbed
  # with paramater a slivergroup-configuration
  #
  s_description "Allocate CONFINE slivers in the slice (id)"
  s_param :sliceid, 'sliceid', 'id of the slice in which you want to allocate slivers'
  s_param :names, 'names', 'array van hostnames'
  s_param :imageid, '[imageid]', 'id of the image you want on the slivers'
  s_param :nwifi, '[nwifi]', 'number of wireless interfaces'
  s_param :neth, '[neth]', 'number of wired interfaces'
  service 'allocateSliverGroup' do |sliceid, names, imageid, nwifi, neth|
	sliverXML = []
	names = names.to_ary
	names_str = names.join(',')
	begin
		slivers = getPortal.createSliverGroup("sliceid" => Integer(sliceid), 
							"names" => names, 
							"imageId" => Integer(imageid), 
							"n_wifi" => Integer(nwifi), 
							"n_eth" => Integer(neth))
		doDB do |inv|
			for i in 0..(names.length-1)
				location_result = inv.addLocation(makeDBLocation(slivers[i]['location']))
				node_result = inv.addNode(makeDBNode(slivers[i]))
				sliverXML[i] = slivers[i]['node']
			end
    		end

		# SliceManagerService.associateResourcesToSlice('experiment.#{sliceid}', names_str, PUBSUB_DOMAIN)

		# SUCCESSFULL
		replyXML = InventoryService.buildXMLReply("SLIVERGROUP", sliverXML, "Failed to allocate a new slivers.") { |root,sliverXML|
			sliverXML.each { |sliverx|
				sliverElem = root.add_element("SLIVER")
				InventoryService.addXMLElement(sliverElem, "HOSTNAME", "#{sliverx['hostname']}")
				InventoryService.addXMLElement(sliverElem, "HRN", "#{sliverx['hrn']}")
      				InventoryService.addXMLElement(sliverElem, "CONTROL_IP", "#{sliverx['control_ip']}")
				InventoryService.addXMLElement(sliverElem, "CONTROL_MAC", "#{sliverx['control_mac']}")
			}
		}
	rescue HTTPStatus::InternalServerError
		raise HTTPStatus::InternalServerError
	rescue Exception => ex
		error ex.message
		replyXML = return_error(ex.message)
	end
    	replyXML
  end

end
