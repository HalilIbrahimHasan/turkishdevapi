package get_http_request_method;

import base_urls.DummyApiBaseUrl;
import com.google.gson.Gson;
import io.restassured.response.Response;
import org.codehaus.jackson.map.ObjectMapper;
import org.junit.Test;
import pojos.Employee;

import java.io.IOException;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.assertTrue;

public class Get10 extends DummyApiBaseUrl {

      /*
      When
        I send a GET Request to the URL http://dummy.restapiexample.com/api/v1/employees

       Status code should be 200
       Use Gson and ObjectMapper

       make sure you have 24 records for data


  */


    @Test
    public void get10() throws IOException {

        //Set the url
        spec.pathParams("bir", "api", "iki", "v1", "uc", "employees");


        //Send the Request and Get the response / Get Request yollayin ve Response elde edin
        Response response = given().spec(spec).when().get("/{bir}/{iki}/{uc}");

        ObjectMapper obj = new ObjectMapper();


        Employee employees = obj.readValue(response.asString(), Employee.class);

        System.out.println(employees.getMessage());
        System.out.println(employees.getStatus());

        for (int i = 0; i < employees.getData().size(); i++) {
            System.out.println("The person "+(i+1)+" name: "+employees.getData().get(i).getEmployee_name());
            System.out.println("The person "+(i+1)+" salary: "+employees.getData().get(i).getEmployee_salary());
            System.out.println("The person "+(i+1)+" id: "+employees.getData().get(i).getId());
        }



        //Validate

        assertTrue("24 records bulunmamakta", employees.getData().size() == 24);

    }



    @Test
    public void get11(){

        //Set the url
        spec.pathParams("bir", "api", "iki", "v1", "uc", "employees");


        //Send the Request and Get the response / Get Request yollayin ve Response elde edin
        Response response = given().spec(spec).when().get("/{bir}/{iki}/{uc}");

        Gson gson = new Gson();

        Employee employees = gson.fromJson(response.asString(), Employee.class);


        System.out.println("Data size: "+ employees.getData().size());

        //Validate

        assertTrue("24 records bulunmamakta", employees.getData().size() == 24);

    }





}

