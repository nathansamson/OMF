#
# Copyright (c) 2006-2009 National ICT Australia (NICTA), Australia
#
# Copyright (c) 2004-2009 WINLAB, Rutgers University, USA
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#
# = ecCommunicator.rb
#
# == Description
#
# This file implements a Publish/Subscribe Communicator for the Node Handler.
# This PubSub communicator is based on XMPP.
# This current implementation uses the library XMPP4R.
#
require "omf-common/omfCommunicator"
require "omf-common/omfProtocol"
require 'omf-expctl/agentCommands'

#
# This class defines a Communicator entity using the Publish/Subscribe paradigm.
# The Node Agent (NA) aka Resource Controller will use this Communicator to
# send/receive messages to/from the Node Handler (EC) aka Experiment Controller
# This Communicator is based on the Singleton design pattern.
#
class ECCommunicator < OmfCommunicator

  SEND_RETRY_INTERVAL = 5 # in sec

  def init(opts)
    super(opts)
    # EC-secific communicator initialisation...
    # 0 - set some attributes
    @@sliceID = opts[:sliceID]
    @@expID = opts[:expID]
    @@retrySending = false
    # 1 - listen to my address (i.e. the is the 'experiment' address)
    addr = create_address(:sliceID => @@sliceID,
                          :expID => @@expID,
                          :domain => @@domain)
    listen(addr)
    # 3 - Set my lists of valid and specific commands
    OmfProtocol::RC_COMMANDS.each { |cmd|
      define_valid_command(cmd) { |comm, message|
        AgentCommands.method(cmd.to_s).call(comm, message)
      }
    }
    # 4 - Set my list of own/self commands
    OmfProtocol::EC_COMMANDS.each { |cmd| define_self_command(cmd) }
  end

  alias parentSend send_message

  #
  # Allow this communicator to retry sending when it failed to send a message
  # Failed messages are put in a queue, which is processed by a separate thread
  # This is because sending of messages can occur from different threads (e.g.
  # a ExecApp thread running a user app) and we should not block that thread, 
  # while we try to resend 
  #
  def allow_retry
    @@retrySending = true
    @@retryQueue = Queue.new
    @@retryThread = Thread.new {
      while element = @@retryQueue.pop do
        success = false
        while !success do
          success = parentSend(element[:addr], element[:msg])
          if !success 
            warn "Failed to send message, retry in #{SEND_RETRY_INTERVAL}s "+
             "(msg: '#{message}')"
            sleep(SEND_RETRY_INTERVAL)
          end
        end
      end
    } 
  end
 
  def reset
    if @@retrySending
      @@retryThread.kill!
      @@retryQueue = nil
      @@retrySending = false
    end
    super
  end

  def send_message(addr, message)
    message.sliceID = @@sliceID
    message.expID = @@expID
    success = super(addr, message)
    if !success && @@retrySending
      @@retryQueue << {:addr => addr, :msg => message}
      return
    end
    warn "Failed to send message! (msg: '#{message}')" if !success
  end

  #
  # Send a NOOP command to a given resource
  # if no resource, then send to all
  #
  def send_noop(resID = nil)
    target = resID ? resID : "*"
    addr = create_address(:sliceID => @@sliceID, :domain => @@domain,
                           :name => resID)
    cmd = create_message(:cmdtype => :NOOP, :target => "#{target}")
    send_message(addr, cmd)
  end

  #
  # Send a RESET command to a given resource
  # if no resource, then send to all
  #
  def send_reset(resID = nil)
    target = resID ? resID : "*"
    cmd = create_message(:cmdtype => :RESET, :target => "#{target}")
    send_message(make_address(:name => resID), cmd)
  end

  def make_address(opts = nil)
    name = opts ? opts[:name] : nil
    return create_address(:sliceID => @@sliceID, :expID => @@expID,
                           :domain => @@domain, :name => name)
  end
  
  private

  def valid_message?(message)
    # 1 - Perform common validations amoung OMF entities
    return false if !super(message)
    # 2 - Perform EC-specific validations
    # - Ignore messages for/from unknown Slice and Experiment ID
    if (message.sliceID != @@sliceID) || (message.expID != @@expID)
      debug "Ignoring message with unknown slice "+
            "and exp IDs: '#{message.sliceID}' and '#{message.expID}'"
      return false
    end
    # - Ignore message from unknown RCs
    if (OMF::EC::Node[message.target] == nil)
      debug "Ignoring command with unknown target '#{message.target}'"
      return false
    end
    # Accept this message
    return true
  end
  
end
