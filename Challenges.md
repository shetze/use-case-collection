Challenges on our way
=====================

The way to an working OpenStack cluster is just a-maze-ing.

Every cluster is different: Any constellation of CPU, RAM, harddrives, NICs, switches and the particular release of the selected software technology creates one point in the universe of possibilities.

Some of these constellations work better than others, some simply fail without reason. Sometimes the very same setup fails the first attempt, the second and the third -- and finally works without any changes. Dont give up, just try it again and again.
And of course, in may cases there is one of the zillion configuration settings available to fix exactly that issue, or to prevent it in the first place. If you could only know which one it is...

The Beostack approach guarantees lots and lots of these experiences. Installing such an cluster is like a huge text adventure, it reminds me of good old [nethack](https://www.nethack.org/index.html).

If you dont love it, just leave it.


Introspection Issues
--------------------

```
Node is registered and manageable, but Power State remains `None`.
```
Mitigation: Shit happens, just start over again.


```
After Introspection, one node remains in `power on` and `clean wait` state.
```
Apparently, the Director does not provide TFTP for that node at that time. It did before and may be next time in the future...
Mitigation: Shit happens, just start over again.





Stack overcloud CREATE_FAILED
-----------------------------



```
TASK [Ensure system is NTP time synced]
no server suitable for synchronization found
```
Mitigation:
* Check the `NtpServer` setting in [network-environment.yaml](/templates/network-environment.yaml)
* Check if the nodes can access the internet (routing, NAT masquerading and such) 
* If everything is fine, just re-start the deployment







```
Heat Stack update failed.
Failure caused by error in tasks: upload_amphora
HTTPConnectionPool(host=\'192.168.1.5\', port=5000): Max retries exceeded
```
Mitigation:
* Make sure director has interface in OpenStack Management Network
  sudo ip addr add 192.168.1.13/24 dev eth0.100
  ( too bad the installation runs all the way through up to this point without complaining... )
