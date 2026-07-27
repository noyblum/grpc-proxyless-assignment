// Command client calls the Greeter service through Cloud Service Mesh.
//
// The target uses the xds:/// scheme: instead of resolving DNS, the gRPC
// library opens an ADS stream to Cloud Service Mesh (per the bootstrap file
// pointed to by GRPC_XDS_BOOTSTRAP), receives listener/route/cluster/endpoint
// configuration for the GRPCRoute hostname, and load-balances every RPC
// across the backend NEG endpoints.
package main

import (
	"context"
	"flag"
	"log"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	xdscreds "google.golang.org/grpc/credentials/xds"
	_ "google.golang.org/grpc/xds" // registers the xds:/// resolver and balancers

	pb "github.com/noyblumenfeld/grpc-hello-app/gen/helloworld"
)

var (
	target   = flag.String("target", "xds:///helloworld-gke", "target URI of the Greeter service")
	interval = flag.Duration("interval", 2*time.Second, "delay between SayHello calls")
)

func main() {
	flag.Parse()

	name, err := os.Hostname()
	if err != nil {
		name = "client"
	}

	// xDS client credentials: use mesh-provided (mTLS) security if Cloud
	// Service Mesh sends it, otherwise fall back to plaintext.
	creds, err := xdscreds.NewClientCredentials(xdscreds.ClientOptions{
		FallbackCreds: insecure.NewCredentials(),
	})
	if err != nil {
		log.Fatalf("failed to create xDS client credentials: %v", err)
	}

	conn, err := grpc.NewClient(*target, grpc.WithTransportCredentials(creds))
	if err != nil {
		log.Fatalf("failed to create channel to %q: %v", *target, err)
	}
	defer conn.Close()

	client := pb.NewGreeterClient(conn)
	log.Printf("calling SayHello on %q every %s", *target, *interval)

	// Call in a loop; the reply message embeds the serving pod's hostname,
	// so the logs demonstrate per-RPC load balancing across server replicas.
	for {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		reply, err := client.SayHello(ctx, &pb.HelloRequest{Name: name})
		cancel()
		if err != nil {
			log.Printf("SayHello failed: %v", err)
		} else {
			log.Printf("reply: %s", reply.GetMessage())
		}
		time.Sleep(*interval)
	}
}
