# Opencomputer-Programs - BaaS Deamon
Bees as a service Deamon this is a simple deamon wrapper for libbaas

## BaaS - Bees as a Service
Bees as a service is a Alveary pooling controller. The intent is to discover drones on the network that would have the following setup:

* Adapter with Tier 3 Database upgrade installed
* N groups: 
    * AdapterBlock
    * ME Interface
    * Transposer
    * Alveary Multiblock structure

* The Controller must have a Adapter block to a ME Interface or ME controller block which is attached to the recieveing network of the resource, this can be the same network but its prefered that is seperated from the bee network,
this is for product level evaluation

A discovery phase is required for identifying drones with those charistics when the service is started
the service attempts to be stateless in the design but where it cannot it will store information in memory and not on disk for the sake of speed

after the discovery phase the service will map species of bees to products and then products to demands
map definition is as follows:
```
{
    "Species name" = {"product name", "..."},
    ...
}
```
Species name and product name can both be unlocalized or localized (ie 'coal' or 'minecraft:coal')

then load a product level map to and attempt to meet demand of a product using a priority round robin scheme
the product configuration format is as follows:
```
{
    "product name" = { count = [integer], priority = [0.0 - 1.0]}
}
```

priority round robin will attempt to keep all requesting products in progress on a round basis driven by percentage based priority value.
the priority will represent a 0-100% utilization of of nodes during the products turn in the round. this means that a product (or products) given a 100% (1) priority will queue for all known nodes in the network.
once all nodes for the specific product have been dispatched then current product will change to the next in line.
once all products have been dispatch the round completes and the next following round will be detirmined based on product levels in the network
this will mean that all pending products will eventually get to have time in N number of nodes.