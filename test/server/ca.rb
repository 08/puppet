if __FILE__ == $0
    $:.unshift '../../lib'
    $:.unshift '..'
    $puppetbase = "../.."
end

require 'puppet'
require 'puppet/server/ca'
require 'puppet/sslcertificates'
require 'openssl'
require 'test/unit'
require 'puppettest.rb'

# $Id$

if ARGV.length > 0 and ARGV[0] == "short"
    $short = true
else
    $short = false
end

class TestCA < Test::Unit::TestCase
	include ServerTest
    # Verify that we're autosigning.  We have to autosign a "different" machine,
    # since we always autosign the CA server's certificate.
    def test_autocertgeneration
        ca = nil

        # create our ca
        assert_nothing_raised {
            ca = Puppet::Server::CA.new(:autosign => true)
        }

        # create a cert with a fake name
        key = nil
        csr = nil
        cert = nil
        hostname = "test.domain.com"
        assert_nothing_raised {
            cert = Puppet::SSLCertificates::Certificate.new(
                :name => "test.domain.com"
            )
        }

        # make the request
        assert_nothing_raised {
            cert.mkcsr
        }

        # and get it signed
        certtext = nil
        cacerttext = nil
        assert_nothing_raised {
            certtext, cacerttext = ca.getcert(cert.csr.to_s)
        }

        # they should both be strings
        assert_instance_of(String, certtext)
        assert_instance_of(String, cacerttext)

        # and they should both be valid certs
        assert_nothing_raised {
            OpenSSL::X509::Certificate.new(certtext)
        }
        assert_nothing_raised {
            OpenSSL::X509::Certificate.new(cacerttext)
        }

        # and pull it again, just to make sure we're getting the same thing
        newtext = nil
        assert_nothing_raised {
            newtext, cacerttext = ca.getcert(
                cert.csr.to_s, "test.reductivelabs.com", "127.0.0.1"
            )
        }

        assert_equal(certtext,newtext)
    end

    # this time don't use autosign
    def test_storeAndSign
        ca = nil
        caserv = nil

        # make our CA server
        assert_nothing_raised {
            caserv = Puppet::Server::CA.new(:autosign => false)
        }

        # retrieve the actual ca object
        assert_nothing_raised {
            ca = caserv.ca
        }

        # make our test cert again
        key = nil
        csr = nil
        cert = nil
        hostname = "test.domain.com"
        assert_nothing_raised {
            cert = Puppet::SSLCertificates::Certificate.new(
                :name => "anothertest.domain.com"
            )
        }
        # and the CSR
        assert_nothing_raised {
            cert.mkcsr
        }

        # retrieve them
        certtext = nil
        assert_nothing_raised {
            certtext, cacerttext = caserv.getcert(
                cert.csr.to_s, "test.reductivelabs.com", "127.0.0.1"
            )
        }

        # verify we got nothing back, since autosign is off
        assert_equal("", certtext)

        # now sign it manually, with the CA object
        x509 = nil
        assert_nothing_raised {
            x509, cacert = ca.sign(cert.csr)
        }

        # and write it out
        cert.cert = x509
        assert_nothing_raised {
            cert.write
        }

        assert(File.exists?(cert.certfile))

        # now get them again, and verify that we actually get them
        newtext = nil
        assert_nothing_raised {
            newtext, cacerttext  = caserv.getcert(cert.csr.to_s)
        }

        assert(newtext)
        assert_nothing_raised {
            OpenSSL::X509::Certificate.new(newtext)
        }

        # Now verify that we can clean a given host's certs
        assert_nothing_raised {
            ca.clean("anothertest.domain.com")
        }

        assert(!File.exists?(cert.certfile), "Cert still exists after clean")
    end

    # and now test the autosign file
    def test_autosign
        autosign = File.join(tmpdir, "autosigntesting")
        @@tmpfiles << autosign
        File.open(autosign, "w") { |f|
            f.puts "hostmatch.domain.com"
            f.puts "*.other.com"
        }

        caserv = nil
        assert_nothing_raised {
            caserv = Puppet::Server::CA.new(:autosign => autosign)
        }

        # make sure we know what's going on
        assert(caserv.autosign?("hostmatch.domain.com"))
        assert(caserv.autosign?("fakehost.other.com"))
        assert(!caserv.autosign?("kirby.reductivelabs.com"))
        assert(!caserv.autosign?("culain.domain.com"))
    end

    # verify that things aren't autosigned by default
    def test_nodefaultautosign
        caserv = nil
        assert_nothing_raised {
            caserv = Puppet::Server::CA.new()
        }

        # make sure we know what's going on
        assert(!caserv.autosign?("hostmatch.domain.com"))
        assert(!caserv.autosign?("fakehost.other.com"))
        assert(!caserv.autosign?("kirby.reductivelabs.com"))
        assert(!caserv.autosign?("culain.domain.com"))
    end

    # We want the CA to autosign its own certificate, because otherwise
    # the puppetmasterd CA does not autostart.
    def test_caautosign
        server = nil
        assert_nothing_raised {
            server = Puppet::Server.new(
                :Port => @@port,
                :Handlers => {
                    :CA => {}, # so that certs autogenerate
                    :Status => nil
                }
            )
        }
    end

    # Make sure true/false causes the file to be ignored.
    def test_autosign_true_beats_file
        caserv = nil
        assert_nothing_raised {
            caserv = Puppet::Server::CA.new()
        }

        host = "hostname.domain.com"

        # Create an autosign file
        file = tempfile()
        Puppet[:autosign] = file

        File.open(file, "w") { |f|
            f.puts host
        }

        # Start with "false"
        Puppet[:autosign] = false

        assert(! caserv.autosign?(host), "Host was incorrectly autosigned")

        # Then set it to true
        Puppet[:autosign] = true
        assert(caserv.autosign?(host), "Host was not autosigned")
        # And try a different host
        assert(caserv.autosign?("other.yay.com"), "Host was not autosigned")

        # And lastly the file
        Puppet[:autosign] = file
        assert(caserv.autosign?(host), "Host was not autosigned")

        # And try a different host
        assert(! caserv.autosign?("other.yay.com"), "Host was autosigned")
    end
end
