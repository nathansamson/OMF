require 'omf-common/web/tab/gmap/gmapServlet'

include OMF::Common

opts = {
    :name => :map, 
    :priority => 400, 
    :def_enabled => false, 
    :view_dir => File.dirname(__FILE__)
}
Web.registerService Web::GMap, opts
