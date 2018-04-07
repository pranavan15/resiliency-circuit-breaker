// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package orderServices;

import ballerina/log;
import ballerina/mime;
import ballerina/net.http;

endpoint http:ServiceEndpoint orderServiceEP {
    port:9090
};

endpoint http:ClientEndpoint circuitBreakerEP {

// The 'circuitBreaker' term incorporate circuit breaker pattern to the client endpoint
// Circuit breaker will immediately drop remote calls if the endpoint exceeded the failure threshold
    circuitBreaker:{
                   // Failure threshold should be in between 0 and 1
                       failureThreshold:0.2,
                   // Reset timeout for circuit breaker should be in milliseconds
                       resetTimeout:10000
                   // httpStatusCodes will have array of http error codes tracked by the circuit breaker
                   //httpStatusCodes:[400, 404, 500]
                   },
    targets:[
            // HTTP client could be any HTTP endpoint that have risk of failure
            {
                uri:"http://localhost:9092"
            }
            ],
    endpointTimeout:2000
};


@http:ServiceConfig {
    basePath:"/order"
}
service<http:Service> orderService bind orderServiceEP {

    @http:ResourceConfig {
        methods:["POST"],
        path:"/"
    }
    orderResource (endpoint httpConnection, http:Request request) {
        // Initialize the request and response message to send to the inventory service
        http:Request outRequest = {};
        http:Response inResponse = {};
        // Initialize the response message to send back to client
        // Extract the items from the json payload
        var result = request.getJsonPayload();
        json items;
        match result {
            json jsonPayload => {
                items = jsonPayload.items;
            }

            mime:EntityError err => {
                http:Response outResponse = {};
                // Send bad request message to the client if request don't contain order items
                outResponse.setStringPayload("Error : Please check the input json payload");
                outResponse.statusCode = 400;
                _ = httpConnection -> respond(outResponse);
                return;
            }
        }

        log:printInfo("Recieved Order : " + items.toString());
        // Set the outgoing request JSON payload with items
        outRequest.setJsonPayload(items);
        // Call the inventory backend through the circuit breaker
        var response = circuitBreakerEP -> post("/inventory", outRequest);
        match response {
            http:Response outResponse => {
            // Send response to the client if the order placement was successful
                outResponse.setStringPayload("Order Placed : " + items.toString());
                _ = httpConnection -> respond(outResponse);
            }
            http:HttpConnectorError err => {
            // If inventory backend contain errors forward the error message to client
                log:printInfo("Inventory service returns an error :" + err.message);
                http:Response outResponse = {};
                outResponse.setJsonPayload({"Error":"Inventory Service did not respond",
                                               "Error_message":err.message});
                _ = httpConnection -> respond(outResponse);
                return;
            }
        }
    }
}
